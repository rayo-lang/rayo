import RayoIR
import RayoSema

/// Where each access of a function is live: from where it begins through the last use of the access, and of every
/// value that depends on it, on each path. Where paths join, an access is live if it is live on any of them.
///
/// Each question is about the points of one block: index `i` is just before the statement at `i`, the number of
/// statements is just before the terminator, and the last index is just after it.
struct AccessExtents {
    private let body: IRBody
    /// What each local's value depends on at each point, carried forward.
    private let dependencies: DataflowResults<DependencyAnalysis>
    /// What code after each point uses, carried backward.
    private let uses: DataflowResults<AccessUseAnalysis>
    /// The accesses that some path to each point has not begun, carried forward.
    private let unbegun: DataflowResults<UnbegunAccessAnalysis>

    /// The extents of the accesses of `places.body`, the body whose places `places` gives the types of, where `uses`
    /// says what code after each of its points uses.
    init(_ places: PlaceTypes, uses: DataflowResults<AccessUseAnalysis>) {
        body = places.body
        dependencies = DataflowSolver.solve(DependencyAnalysis(), in: places.body)
        self.uses = uses
        unbegun = DataflowSolver.solve(UnbegunAccessAnalysis(places.body), in: places.body)
    }

    /// The accesses live at each point of `block`; nil where no path reaches the block.
    func live(in block: BlockID) -> [Set<AccessID>]? {
        let points = body.blocks[block.index].statements.count + 2

        // Walk back through what later code uses, keeping at each point the accesses it uses and the locals it reads.
        var used = Array(repeating: (accesses: Set<AccessID>(), readLocals: Set<LocalID>()), count: points)
        let reached = uses.walk(block) { point, state in
            used[point] = (state.accesses, state.values.readLocals)
        }
        guard reached else { return nil }

        // Walk forward through what values depend on, which carries the uses to the accesses behind them.
        var live = Array(repeating: Set<AccessID>(), count: points)
        dependencies.walk(block) { point, state in
            live[point] = Self.live(using: used[point], dependingOn: state)
        }
        return live
    }

    /// Of the accesses `live` at each point of `block`, those that every path there has begun. Only they can end
    /// there, since a path that hasn't begun an access has nothing to end.
    func held(in block: BlockID, live: [Set<AccessID>]) -> [Set<AccessID>] {
        var held = live
        unbegun.walk(block) { point, state in
            held[point] = live[point].filter { !state.accesses.contains($0) }
        }
        return held
    }

    /// The accesses live at a point where later code uses `uses.accesses` and reads values inside `uses.readLocals`,
    /// and values depend on what `dependencies` holds: those the code uses, those they depend on, and those that the
    /// values it reads depend on.
    private static func live(
        using uses: (accesses: Set<AccessID>, readLocals: Set<LocalID>), dependingOn dependencies: DependencyState,
    ) -> Set<AccessID> {
        var live = uses.accesses
        for access in uses.accesses {
            live.formUnion(dependencies.dependencies(of: access))
        }
        for local in uses.readLocals {
            live.formUnion(dependencies.dependentLocals[local] ?? [])
        }
        return live
    }
}
