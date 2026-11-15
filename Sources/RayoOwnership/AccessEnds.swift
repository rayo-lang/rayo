import RayoIR

/// Writes the end of each access of a function into its body, after the last point on each path where it is live.
/// Where a branch leaves for a block that the access isn't live in, the access ends on the way into that block.
enum AccessEnds {
    /// `body` with the end of each access written into it, where `live` holds the accesses live at each point of
    /// each block, counted as `AccessExtents` counts its points, or nil for a block that no path reaches.
    static func written(into body: IRBody, live: [[Set<AccessID>]?]) -> IRBody {
        var ended = body
        var edges: [EdgeStatements] = []
        for (index, blockLive) in live.enumerated() {
            // A block that no path reaches begins no access that runs.
            guard let blockLive else { continue }
            let block = BlockID(index: index)
            ended.blocks[index] = endingInside(body.blocks[index], live: blockLive)

            // An edge ends the accesses live before the block's terminator that aren't live where its target begins.
            let leaving = blockLive[body.blocks[index].statements.count]
            edges += EdgeStatements.leaving(block, of: body) { target in
                ends(of: leaving.subtracting(live[target.index]?.first ?? []))
            }
        }
        return EdgeStatements.written(edges, into: ended)
    }

    /// `block` with the end of each access that stops being live at one of its statements written in after it.
    private static func endingInside(_ block: BasicBlock, live: [Set<AccessID>]) -> BasicBlock {
        var statements: [Statement] = []
        for (index, statement) in block.statements.enumerated() {
            statements.append(statement)

            // An access ends after the statement that it is live before, or that begins it, where it isn't live after.
            var ending = live[index]
            if case .begin(let id, _) = statement { ending.insert(id) }
            statements += ends(of: ending.subtracting(live[index + 1]))
        }
        return BasicBlock(statements: statements, terminator: block.terminator)
    }

    /// The statements that end `accesses`, the highest-numbered first, so that accesses end in the reverse of the
    /// order lowering numbers them as it begins them.
    private static func ends(of accesses: Set<AccessID>) -> [Statement] {
        accesses.sorted(by: >).map(Statement.end)
    }
}
