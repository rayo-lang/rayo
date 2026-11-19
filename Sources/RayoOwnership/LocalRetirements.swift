import RayoCheckedProgram
import RayoIR

/// Writes the retirement of each local that a declaration starts the life of into a function's body, after the last
/// point on each path where later code uses it before a declaration starts its life again. A local that no
/// declaration starts, such as a parameter, lives as long as the call, and never retires.
enum LocalRetirements {
    /// `body` with the retirement of each local it declares written into it.
    static func written(into body: IRBody) -> IRBody {
        // A body that declares no local has none to retire.
        let declared = declaredLocals(in: body)
        guard !declared.isEmpty else { return body }

        let inUse = localsInUse(in: body, among: declared)
        var retired = body
        var edges: [EdgeStatements] = []
        for (index, blockInUse) in inUse.enumerated() {
            // A block that no path reaches uses no local.
            guard let blockInUse else { continue }
            let block = BlockID(index: index)
            retired.blocks[index] = retiringInside(body.blocks[index], inUse: blockInUse)

            // An edge retires the locals in use before the block's terminator that aren't where its target begins.
            let leaving = blockInUse[body.blocks[index].statements.count]
            edges += EdgeStatements.leaving(block, of: body) { target in
                retirements(of: leaving.subtracting(inUse[target.index]?.first ?? []))
            }
        }
        return EdgeStatements.written(edges, into: retired)
    }

    /// The locals of `declared` that later code in `body` uses at each point of each block, counted as
    /// `DataflowResults` counts a block's points, or nil for a block that no path reaches.
    private static func localsInUse(in body: IRBody, among declared: Set<LocalID>) -> [[Set<LocalID>]?] {
        let uses = DataflowSolver.solve(from: LocalUseState(), through: body, knowing: LocalUses(body))
        return body.blocks.indices.map { index in
            var inUse = Array(repeating: Set<LocalID>(), count: body.blocks[index].statements.count + 2)
            let reached = uses.walk(BlockID(index: index)) { point, state in
                inUse[point] = state.locals.intersection(declared)
            }
            return reached ? inUse : nil
        }
    }

    /// The locals that some statement of `body` declares.
    private static func declaredLocals(in body: IRBody) -> Set<LocalID> {
        var declared: Set<LocalID> = []
        for case .declare(let local) in body.blocks.flatMap(\.statements).flatMap(\.effects) {
            declared.insert(local)
        }
        return declared
    }

    /// `block` with the retirement of each local that stops being in use at one of its statements written in after
    /// it. A terminator that leaves the function retires nothing, since the function's return ends every life.
    private static func retiringInside(_ block: BasicBlock, inUse: [Set<LocalID>]) -> BasicBlock {
        var statements: [Statement] = []
        for (index, statement) in block.statements.enumerated() {
            statements.append(statement)

            // A local retires after the statement that it is in use before, or that declares it, where it isn't in
            // use after.
            var retiring = inUse[index]
            for case .declare(let local) in statement.effects { retiring.insert(local) }
            statements += retirements(of: retiring.subtracting(inUse[index + 1]))
        }
        return BasicBlock(statements: statements, terminator: block.terminator)
    }

    /// The statements that retire `locals`, in the order of their IDs.
    private static func retirements(of locals: Set<LocalID>) -> [Statement] {
        locals.sorted().map(Statement.retire)
    }
}
