import RayoCheckedProgram
import RayoIR

/// Where each access of a function is live: from where it begins through its last use on each path, and through the
/// last use of every value that depends on it. Where paths join, an access is live if it is live on any of them.
///
/// Each question is about the points of one block: index `i` is just before the statement at `i`, the number of
/// statements is just before the terminator, and the last index is just after it.
struct AccessExtents {
    private let body: IRBody
    /// What code after each point uses, carried backward.
    private let uses: DataflowResults<AccessUseState>
    /// What each local's value depends on at each point, carried forward.
    private let dependencies: DataflowResults<DependencyState>
    /// The accesses that some path to each point has not begun, carried forward.
    private let unbegun: DataflowResults<UnbegunAccessState>

    /// The extents of the accesses of `body`, where `uses` says what code after each of its points uses.
    init(_ body: IRBody, uses: DataflowResults<AccessUseState>) {
        self.body = body
        self.uses = uses

        let (dependencyEntry, unbegunEntry) = Self.entryStates(of: body)
        dependencies = DataflowSolver.solve(from: dependencyEntry, through: body, knowing: ())
        unbegun = DataflowSolver.solve(from: unbegunEntry, through: body, knowing: ())
    }

    /// The dependence and unbegun-access states on entry to `body`, which the extents carry through it.
    private static func entryStates(of body: IRBody) -> (dependencies: DependencyState, unbegun: UnbegunAccessState) {
        // The states index accesses by their IDs, so they span every ID the body begins.
        let highestID = body.begunAccesses.keys.max()
        let accessCount = highestID.map { $0.index + 1 } ?? 0
        return (DependencyState(entering: body, accessCount: accessCount), UnbegunAccessState(accessCount: accessCount))
    }

    /// The accesses live at each point of `block`: those that code after the point uses, those the values it reads
    /// depend on, and those that these depend on in turn. Nil where no path reaches the block.
    func live(in block: BlockID) -> [Set<AccessID>]? {
        let points = body.blocks[block.index].statements.count + 2

        // Walk back through what later code uses, keeping at each point the accesses it uses and the locals it reads.
        var used = Array(repeating: LaterUses(accesses: [], readLocals: []), count: points)
        let reached = uses.walk(block) { point, state in used[point] = LaterUses(state) }
        guard reached else { return nil }

        // Walk forward through what values depend on, which carries the uses to the accesses behind them.
        var live = Array(repeating: Set<AccessID>(), count: points)
        dependencies.walk(block) { point, state in
            live[point] = Self.live(using: used[point], dependingOn: state)
        }
        return live
    }

    /// The accesses live just after each effect of `block`, by the rule `live(in:)` keeps between statements: one set
    /// for each effect of its statements in turn, then of its terminator. Nil where no path reaches the block.
    func liveAfterEffects(in block: BlockID) -> [Set<AccessID>]? {
        // Walk back through what later code uses, keeping what the code after each effect uses, the last effect first.
        var used: [LaterUses] = []
        let reached = uses.walkEffects(of: block) { _, state in used.append(LaterUses(state)) }
        guard reached else { return nil }

        // Walk forward through what values depend on once each effect is done, which carries the uses after the
        // effect to the accesses behind them.
        var live: [Set<AccessID>] = []
        dependencies.walkEffects(of: block) { effect, before in
            var after = before
            after.apply(effect, in: ())
            live.append(Self.live(using: used[used.count - 1 - live.count], dependingOn: after))
        }
        return live
    }

    /// The accesses held at each point of each block, given those `live` there, or nil for a block that no path
    /// reaches: each that is live at the point or at a later point of some path from it, before anything begins it
    /// again, and that every path to the point has begun. So each path into a block holds every access the block holds
    /// where it begins, and no path ends one that another still holds there. Only a held access can end, since a path
    /// that hasn't begun an access has nothing to end.
    func held(given live: [[Set<AccessID>]?]) -> [[Set<AccessID>]?] {
        let needed = carriedBack(live)
        return needed.indices.map { index in
            guard let points = needed[index] else { return nil }
            var held = points
            unbegun.walk(BlockID(index: index)) { point, state in
                held[point] = points[point].filter { !state.contains($0) }
            }
            return held
        }
    }

    /// `live` carried back along every path: each access live at a point is also in the set at each point before it,
    /// back to the statement that begins it. Where paths join, each path into the join takes what is live where the
    /// join begins.
    private func carriedBack(_ live: [[Set<AccessID>]?]) -> [[Set<AccessID>]?] {
        var carried = live
        var changed = true
        while changed {
            changed = false
            for index in body.blocks.indices.reversed() {
                guard let points = carried[index] else { continue }
                let block = body.blocks[index]

                // After the terminator, the block needs what each block it goes to needs where that block begins.
                var next = points
                for successor in block.terminator.successors {
                    next[next.count - 1].formUnion(carried[successor.index]?.first ?? [])
                }

                // Before the terminator and each statement, it needs what the point after needs, but for an access
                // the statement begins.
                next[block.statements.count].formUnion(next[block.statements.count + 1])
                for statement in block.statements.indices.reversed() {
                    var after = next[statement + 1]
                    for case .begin(let id, _) in block.statements[statement].effects { after.remove(id) }
                    next[statement].formUnion(after)
                }

                if next != points {
                    carried[index] = next
                    changed = true
                }
            }
        }
        return carried
    }

    /// The accesses live at a point where later code does what `uses` holds, and values depend on what `dependencies`
    /// holds: those the code uses, those they depend on, and those that the values it reads depend on.
    private static func live(using uses: LaterUses, dependingOn dependencies: DependencyState) -> Set<AccessID> {
        var live = uses.accesses
        for access in uses.accesses {
            live.formUnion(dependencies.dependencies(of: access))
        }
        for local in uses.readLocals {
            live.formUnion(dependencies.dependencies(of: local))
        }
        return live
    }
}

/// What the code after a point uses: the accesses it uses, and the locals it reads a value inside.
private struct LaterUses {
    var accesses: Set<AccessID>
    var readLocals: Set<LocalID>

    init(accesses: Set<AccessID>, readLocals: Set<LocalID>) {
        self.accesses = accesses
        self.readLocals = readLocals
    }

    /// What the code after the point of `state` uses.
    init(_ state: AccessUseState) {
        self.init(accesses: state.accesses.ids, readLocals: state.values.readLocals)
    }
}
