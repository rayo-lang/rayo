import RayoIR

/// Statements that run on one edge from a block to a successor, such as the ends of what is held as the edge leaves
/// the block and not as it enters the successor.
struct EdgeStatements {
    var source: BlockID
    /// The edge's place among `source`'s successors.
    var edge: Int
    var target: BlockID
    var statements: [Statement]

    /// The statements that each edge out of `block`, a block of `body`, runs: those that `statements` makes for the
    /// edge's target, leaving out each edge it makes none for.
    static func leaving(
        _ block: BlockID, of body: IRBody, _ statements: (BlockID) -> [Statement],
    ) -> [EdgeStatements] {
        body.blocks[block.index].terminator.successors.enumerated().compactMap { edge, target in
            let running = statements(target)
            guard !running.isEmpty else { return nil }
            return EdgeStatements(source: block, edge: edge, target: target, statements: running)
        }
    }

    /// `body` with each of `edges`' statements written on its edge: at the start of a target that no other edge
    /// enters, and otherwise in a new block on the edge, which then goes on to the target.
    static func written(_ edges: [EdgeStatements], into body: IRBody) -> IRBody {
        var written = body
        let entries = incomingEdgeCounts(of: body)
        for edge in edges {
            if entries[edge.target.index] == 1 {
                written.blocks[edge.target.index].statements.insert(contentsOf: edge.statements, at: 0)
            } else {
                let block = BlockID(index: written.blocks.count)
                written.blocks.append(BasicBlock(statements: edge.statements, terminator: .goto(edge.target)))
                let terminator = written.blocks[edge.source.index].terminator
                written.blocks[edge.source.index].terminator = terminator.replacingSuccessor(at: edge.edge, with: block)
            }
        }
        return written
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
