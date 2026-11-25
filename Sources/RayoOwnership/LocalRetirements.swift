import RayoCheckedProgram
import RayoIR

/// Writes the retirement of each local that a declaration starts the life of into a function's body, after the last
/// point on each path where later code uses it before a declaration starts its life again. A local that no
/// declaration starts, such as a parameter, lives as long as the call, and never retires. It holds one body, and
/// which locals later code uses at each point of it.
struct LocalRetirements {
    private let body: IRBody
    /// The locals that some statement of the body declares.
    private let declared: Set<LocalID>
    private let localUses: LocalUses
    /// Which locals later code uses at each point of the body.
    private let useStates: DataflowResults<LocalUseState>

    /// `body` with the retirement of each local it declares written into it.
    static func written(into body: IRBody) -> IRBody {
        // A body that declares no local has none to retire.
        let declared = declaredLocals(in: body)
        guard !declared.isEmpty else { return body }

        return LocalRetirements(body: body, declared: declared).written()
    }

    private init(body: IRBody, declared: Set<LocalID>) {
        self.body = body
        self.declared = declared
        localUses = LocalUses(body)
        useStates = DataflowSolver.solve(from: LocalUseState(leaving: body), through: body, knowing: localUses)
    }

    /// The locals that some statement of `body` declares.
    private static func declaredLocals(in body: IRBody) -> Set<LocalID> {
        var declared: Set<LocalID> = []
        for block in body.blocks {
            for statement in block.statements {
                statement.forEachEffect { effect in
                    if case .declare(let local) = effect { declared.insert(local) }
                }
            }
        }
        return declared
    }

    /// The body with the retirements written in after its statements and on its edges.
    private func written() -> IRBody {
        let walked = body.blocks.indices.map { retiringInside(BlockID(index: $0)) }
        var retired = body
        var edges: [EdgeStatements] = []
        for (index, walk) in walked.enumerated() {
            // A block that no path reaches uses no local.
            guard let walk else { continue }
            let block = BlockID(index: index)
            retired.blocks[index] = walk.block

            edges += EdgeStatements.leaving(block, of: body) { target in
                guard let entry = walked[target.index]?.entry else {
                    preconditionFailure("a path that reaches a block reaches each block it goes on to")
                }
                return retirements(onEdgeFrom: walk, into: entry)
            }
        }
        return EdgeStatements.written(edges, into: retired)
    }

    /// `block` with the retirement of each local that stops being in use at one of its statements written in after
    /// it, or nil for a block that no path reaches. A terminator that leaves the function retires nothing, since the
    /// function's return ends every life.
    private func retiringInside(_ block: BlockID) -> RetiringBlock? {
        let statements = body.blocks[block.index].statements
        var retirementsAfter = Array(repeating: [Statement](), count: statements.count)
        var entry: LocalUseState?
        var exit: LocalUseState?
        useStates.walk(block) { point, state in
            if point == 0 { entry = state }
            if point == statements.count + 1 { exit = state }
            // Each point from the second through the one just before the terminator lies just after a statement.
            guard point > 0, point <= statements.count else { return }
            retirementsAfter[point - 1] = retirements(after: statements[point - 1], unusedIn: state)
        }
        guard let entry, let exit else { return nil }

        var retired: [Statement] = []
        for (statement, retirements) in zip(statements, retirementsAfter) {
            retired.append(statement)
            retired += retirements
        }
        let written = BasicBlock(statements: retired, terminator: body.blocks[block.index].terminator)
        return RetiringBlock(block: written, entry: entry, exit: exit)
    }

    /// The statements that retire each declared local that `statement` declares or uses, and that no code after it
    /// uses, as `after` says.
    private func retirements(after statement: Statement, unusedIn after: LocalUseState) -> [Statement] {
        // Only a declaration or a retirement takes a local out of use, so a local in use before a statement and not
        // after it is one the statement uses. A declaration's life ends at once where no code after it uses the local.
        var retiring: Set<LocalID> = []
        statement.forEachEffect { effect in
            let named = if case .declare(let local) = effect { local } else { localUses.local(usedBy: effect) }
            guard let named, declared.contains(named), !after.uses(named) else { return }
            retiring.insert(named)
        }
        return retirements(of: retiring)
    }

    /// The statements that retire, on an edge from `walk` into a block that begins where `entry` holds, each declared
    /// local in use before the walked block's terminator and not where the edge goes.
    private func retirements(onEdgeFrom walk: RetiringBlock, into entry: LocalUseState) -> [Statement] {
        // After the terminator, later code uses what the blocks it goes on to use where they begin, so that state
        // shares most of its parts with the target's, and comparing the two costs only the parts that differ.
        var retiring = Set(walk.exit.localsUsed(notUsedIn: entry).filter(declared.contains))

        // The terminator may use a local itself, such as a branch's condition, that the target doesn't.
        for effect in walk.block.terminator.effects {
            guard let local = localUses.local(usedBy: effect), declared.contains(local), !entry.uses(local) else {
                continue
            }
            retiring.insert(local)
        }
        return retirements(of: retiring)
    }

    /// The statements that retire `locals`, in the order of their IDs.
    private func retirements(of locals: Set<LocalID>) -> [Statement] {
        locals.sorted().map(Statement.retire)
    }
}

/// A block with the retirements that its statements make written in, and what later code uses at its two ends, which
/// the edges into and out of it retire by.
private struct RetiringBlock {
    let block: BasicBlock
    /// What later code uses where the block begins.
    let entry: LocalUseState
    /// What later code uses just after the block's terminator.
    let exit: LocalUseState
}
