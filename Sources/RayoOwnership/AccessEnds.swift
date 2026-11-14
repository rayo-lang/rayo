import RayoIR

/// Writes the end of each access of a function into its body, after the access's last live point on each path.
enum AccessEnds {
    /// The ends that an edge from one block to another needs: those of the accesses live as the edge leaves `source`
    /// and dead as it enters its target.
    private struct EdgeEnds {
        var source: BlockID
        /// The edge's place among `source`'s successors.
        var edge: Int
        var target: BlockID
        var ends: Set<AccessID>
    }

    /// `body` with the end of each access written into it, where `live` holds the accesses live at each point of
    /// each block, as `AccessExtents.live(in:)` gives them, or nil for a block that no path reaches.
    static func written(into body: IRBody, live: [[Set<AccessID>]?]) -> IRBody {
        var ended = body
        var edges: [EdgeEnds] = []
        for (index, blockLive) in live.enumerated() {
            // A block that no path reaches begins no access that runs.
            guard let blockLive else { continue }
            let block = BlockID(index: index)
            ended.blocks[index] = endingInside(body.blocks[index], live: blockLive)
            edges += endsOnEdges(leaving: block, of: body, live: blockLive, entryLive: { live[$0.index]?.first ?? [] })
        }
        return endingOnEdges(edges, in: ended)
    }

    /// `block` with the end of each access that stops being live at one of its statements, or at its terminator
    /// where that leaves the function, written in after it.
    private static func endingInside(_ block: BasicBlock, live: [Set<AccessID>]) -> BasicBlock {
        var statements: [Statement] = []
        for (index, statement) in block.statements.enumerated() {
            statements.append(statement)

            // An access ends after the statement that it is live before, or that begins it, where it is dead after.
            var ending = live[index]
            if case .begin(let id, _) = statement { ending.insert(id) }
            statements += ends(of: ending.subtracting(live[index + 1]))
        }

        // A terminator that leaves the function ends every access still live, just before it goes, since a function
        // returns no value that depends on an access it began.
        if block.terminator.successors.isEmpty { statements += ends(of: live[block.statements.count]) }
        return BasicBlock(statements: statements, terminator: block.terminator)
    }

    /// The ends that each edge out of `block`, a block of `body`, needs: those of the accesses live before its
    /// terminator, which `live` gives, that `entryLive` doesn't give as live where the edge's target begins.
    private static func endsOnEdges(
        leaving block: BlockID, of body: IRBody, live: [Set<AccessID>], entryLive: (BlockID) -> Set<AccessID>,
    ) -> [EdgeEnds] {
        let leaving = live[body.blocks[block.index].statements.count]
        return body.blocks[block.index].terminator.successors.enumerated().compactMap { edge, target in
            let ending = leaving.subtracting(entryLive(target))
            guard !ending.isEmpty else { return nil }
            return EdgeEnds(source: block, edge: edge, target: target, ends: ending)
        }
    }

    /// `body` with `edges`' ends written on their edges: at the start of a target that no other edge enters, and
    /// otherwise in a new block on the edge, which then goes on to the target.
    private static func endingOnEdges(_ edges: [EdgeEnds], in body: IRBody) -> IRBody {
        var ended = body
        let entries = incomingEdgeCounts(of: body)
        for edge in edges {
            let statements = ends(of: edge.ends)
            if entries[edge.target.index] == 1 {
                ended.blocks[edge.target.index].statements.insert(contentsOf: statements, at: 0)
            } else {
                let block = BlockID(index: ended.blocks.count)
                ended.blocks.append(BasicBlock(statements: statements, terminator: .goto(edge.target)))
                let terminator = ended.blocks[edge.source.index].terminator
                ended.blocks[edge.source.index].terminator = terminator.replacingSuccessor(at: edge.edge, with: block)
            }
        }
        return ended
    }

    /// How many ways enter each block of `body`, by `BlockID`: the edges from every block, reached or not, and the
    /// function's entry, which enters the first block.
    private static func incomingEdgeCounts(of body: IRBody) -> [Int] {
        var counts = Array(repeating: 0, count: body.blocks.count)
        counts[0] = 1
        for target in body.blocks.flatMap(\.terminator.successors) {
            counts[target.index] += 1
        }
        return counts
    }

    /// The statements that end `accesses`, the highest-numbered first, so that accesses end in the reverse of the
    /// order lowering numbers them as it begins them.
    private static func ends(of accesses: Set<AccessID>) -> [Statement] {
        accesses.sorted(by: >).map(Statement.end)
    }
}

private extension Terminator {
    /// The terminator with the successor at `index` among its successors replaced by `block`.
    func replacingSuccessor(at index: Int, with block: BlockID) -> Terminator {
        switch self {
        case .goto: .goto(block)
        case .branch(let condition, let then, let otherwise):
            index == 0 ? .branch(condition, then: block, otherwise: otherwise)
                : .branch(condition, then: then, otherwise: block)
        case .return, .unreachable: preconditionFailure("a terminator that leaves the function has no successors")
        }
    }
}
