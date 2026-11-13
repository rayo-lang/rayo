import RayoIR

/// The blocks of a function that some path from its entry reaches, in the orders a dataflow solver visits them.
struct BlockOrder {
    /// The reached blocks, each after the blocks it leads to, except along an edge back to a block whose walk is
    /// still under way, such as a loop's header.
    private(set) var postorder: [BlockID] = []
    /// The reached blocks that lead to each block, indexed by `BlockID`.
    private(set) var predecessors: [[BlockID]]

    init(_ body: IRBody) {
        predecessors = Array(repeating: [], count: body.blocks.count)
        var isReached = Array(repeating: false, count: body.blocks.count)

        // Walk depth first from the entry, holding the path walked so far and how many of each block's successors
        // it has followed. A block joins the postorder once all its successors are followed.
        var path: [(block: BlockID, followed: Int)] = [(BlockID(index: 0), 0)]
        isReached[0] = true
        while let (block, followed) = path.last {
            let successors = body.blocks[block.index].terminator.successors
            guard followed < successors.count else {
                postorder.append(block)
                path.removeLast()
                continue
            }

            // Follow the next successor, and walk on from it the first time it is reached.
            path[path.count - 1].followed += 1
            let successor = successors[followed]
            predecessors[successor.index].append(block)
            guard !isReached[successor.index] else { continue }
            isReached[successor.index] = true
            path.append((successor, 0))
        }
    }
}
