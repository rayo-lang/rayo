import RayoIR

/// Carries a dataflow analysis's state through a function's blocks until the state at each block's boundary settles:
/// at its entry going forward, and at its exit going backward.
struct DataflowSolver<Analysis: DataflowAnalysis> {
    private let analysis: Analysis
    private let body: IRBody
    private let order: BlockOrder
    /// The state at each block's boundary so far, indexed by `BlockID`; nil for a block that no state has reached yet.
    private var boundaryStates: [Analysis.State?]
    /// The blocks whose boundary state has changed since the solver last carried it through them.
    private var pending: WorkQueue

    /// Solves `analysis` through `body`, and returns the settled states.
    static func solve(_ analysis: Analysis, in body: IRBody) -> DataflowResults<Analysis> {
        var solver = DataflowSolver(analysis, in: body)
        solver.settle()
        return DataflowResults(analysis, in: body, boundaryStates: solver.boundaryStates)
    }

    private init(_ analysis: Analysis, in body: IRBody) {
        self.analysis = analysis
        self.body = body
        order = BlockOrder(body)
        boundaryStates = Array(repeating: nil, count: body.blocks.count)

        // The walk begins at the function's entry going forward, and at each reached exit going backward. Going
        // forward, reverse postorder visits each block after the blocks that lead to it, outside loops; going
        // backward, postorder visits each block after those it leads to.
        switch analysis.direction {
        case .forward:
            boundaryStates[0] = analysis.startState
            pending = WorkQueue(order.postorder.reversed(), blockCount: body.blocks.count)
        case .backward:
            for block in order.postorder where body.blocks[block.index].terminator.successors.isEmpty {
                boundaryStates[block.index] = analysis.startState
            }
            pending = WorkQueue(order.postorder, blockCount: body.blocks.count)
        }
    }

    /// Carries each pending block's state through it to the blocks it flows into, until no boundary state changes.
    private mutating func settle() {
        while let block = pending.pop() {
            // A block that no state has reached yet has nothing to hand on.
            guard var state = boundaryStates[block.index] else { continue }
            analysis.apply(across: body.blocks[block.index], to: &state)

            // Each block the state flows into is pending again where the state adds to its own.
            for next in blocks(after: block) where merge(state, intoBoundaryOf: next) {
                pending.push(next)
            }
        }
    }

    /// The blocks that `block`'s state flows into: its successors going forward, and the reached blocks that lead
    /// to it going backward.
    private func blocks(after block: BlockID) -> [BlockID] {
        switch analysis.direction {
        case .forward: body.blocks[block.index].terminator.successors
        case .backward: order.predecessors[block.index]
        }
    }

    /// Merges `state` into the state at `block`'s boundary, and returns whether that changed it.
    private mutating func merge(_ state: Analysis.State, intoBoundaryOf block: BlockID) -> Bool {
        guard let previous = boundaryStates[block.index] else {
            boundaryStates[block.index] = state
            return true
        }

        // A merge that dropped part of the previous state could swing back and forth forever, so it stops the
        // solver here, in debug builds, rather than there.
        let merged = previous.merged(with: state)
        assert(merged.merged(with: previous) == merged, "a dataflow merge must only grow a block's state")

        guard merged != previous else { return false }
        boundaryStates[block.index] = merged
        return true
    }
}

/// Blocks waiting their turn, first in first out, each at most once at a time.
private struct WorkQueue {
    private var blocks: [BlockID]
    /// The index in `blocks` of the next block to hand out; those before it are handed out.
    private var head = 0
    /// Whether each block is waiting, indexed by `BlockID`.
    private var isWaiting: [Bool]

    /// A queue of `blocks`, in their order, from a function of `blockCount` blocks.
    init(_ blocks: [BlockID], blockCount: Int) {
        self.blocks = blocks
        isWaiting = Array(repeating: false, count: blockCount)
        for block in blocks {
            isWaiting[block.index] = true
        }
    }

    /// Adds `block` at the back, unless it is already waiting.
    mutating func push(_ block: BlockID) {
        guard !isWaiting[block.index] else { return }
        isWaiting[block.index] = true
        blocks.append(block)
    }

    /// Takes the block at the front, or returns nil when none is waiting.
    mutating func pop() -> BlockID? {
        guard head < blocks.count else { return nil }
        let block = blocks[head]
        isWaiting[block.index] = false
        head += 1

        // Drop the blocks handed out once they fill half the storage, so it grows only with the blocks waiting.
        if head * 2 >= blocks.count {
            blocks.removeFirst(head)
            head = 0
        }
        return block
    }
}
