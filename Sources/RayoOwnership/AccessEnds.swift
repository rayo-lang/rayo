import RayoIR

/// Writes the end of each access of a function into its body, after the last point on each path where it is held:
/// live, and begun on every path there. Where a path that never began an access joins one where a value still depends
/// on it, the access ends on the way into the join, since no end may run on a path that has nothing to end.
enum AccessEnds {
    /// `body` with the end of each access written into it, where `held` holds the accesses held at each point of
    /// each block, counted as `AccessExtents` counts its points, or nil for a block that no path reaches.
    static func written(into body: IRBody, held: [[Set<AccessID>]?]) -> IRBody {
        var ended = body
        var edges: [EdgeStatements] = []
        for (index, blockHeld) in held.enumerated() {
            // A block that no path reaches begins no access that runs.
            guard let blockHeld else { continue }
            let block = BlockID(index: index)
            ended.blocks[index] = endingInside(body.blocks[index], held: blockHeld)

            // An edge ends the accesses held before the block's terminator that aren't held where its target begins.
            let leaving = blockHeld[body.blocks[index].statements.count]
            edges += EdgeStatements.leaving(block, of: body) { target in
                ends(of: leaving.subtracting(held[target.index]?.first ?? []))
            }
        }
        return EdgeStatements.written(edges, into: ended)
    }

    /// `block` with the end of each access that stops being held at one of its statements, or at its terminator
    /// where that leaves the function, written in after it.
    private static func endingInside(_ block: BasicBlock, held: [Set<AccessID>]) -> BasicBlock {
        var statements: [Statement] = []
        for (index, statement) in block.statements.enumerated() {
            statements.append(statement)

            // An access ends after the statement that it is held before, or that begins it, where it isn't held
            // after.
            var ending = held[index]
            for case .begin(let id, _) in statement.effects { ending.insert(id) }
            statements += ends(of: ending.subtracting(held[index + 1]))
        }

        // A terminator that leaves the function ends every access still held, such as one a value that the
        // terminator reads depends on, just before it goes, since no code after it can.
        if block.terminator.successors.isEmpty { statements += ends(of: held[block.statements.count]) }
        return BasicBlock(statements: statements, terminator: block.terminator)
    }

    /// The statements that end `accesses`, the highest-numbered first, so that accesses end in the reverse of the
    /// order lowering numbers them as it begins them.
    private static func ends(of accesses: Set<AccessID>) -> [Statement] {
        accesses.sorted(by: >).map(Statement.end)
    }
}
