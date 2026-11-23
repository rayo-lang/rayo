import RayoIR

/// Carries a dataflow analysis's state through a function's blocks until the state at each block's boundary settles:
/// at its entry going forward, and at its exit going backward.
struct DataflowSolver<State: DataflowState> {
    private let body: IRBody
    /// The effects of each block's statements and terminator, indexed by `BlockID`, as `BasicBlock.effects` gives them.
    private let effects: [[[Effect]]]
    /// What the state needs to know of the function.
    private let function: State.Function
    private let direction: DataflowDirection
    private let order: BlockOrder
    /// The state at each block's boundary so far, indexed by `BlockID`; nil for a block that no state has reached yet,
    /// or that no path from the entry reaches.
    private var boundaryStates: [State?]
    /// The blocks whose boundary state has changed since the solver last carried it through them.
    private var pending: WorkQueue

    /// Carries the state through `body` from `start`, and returns the settled states. The walk begins on entry to the
    /// function going forward. Going backward, `start` is the state at the exit of every block, which the states of
    /// the paths out of the block merge into: so it is the state at the function's exits, and it must add nothing to
    /// a merge. `function` is what the state needs to know of `body`.
    static func solve(
        from start: State, through body: IRBody, knowing function: State.Function,
    ) -> DataflowResults<State> {
        var solver = DataflowSolver(from: start, through: body, knowing: function)
        solver.settle()
        return DataflowResults(effects: solver.effects, function: function, boundaryStates: solver.boundaryStates)
    }

    private init(from start: State, through body: IRBody, knowing function: State.Function) {
        self.body = body
        effects = body.blocks.map(\.effects)
        self.function = function
        direction = start.direction
        order = BlockOrder(body)
        boundaryStates = Array(repeating: nil, count: body.blocks.count)

        // The walk begins at the function's entry going forward, and at the exit of each reached block going
        // backward, so that a loop that no path leaves has a state too. Going backward, postorder visits each block
        // after those it leads to.
        switch direction {
        case .forward:
            boundaryStates[0] = start
            let forwardOrder = LoopNestOrder(body, reached: order.postorder.reversed())
            pending = WorkQueue(forwardOrder.blocks, blockCount: body.blocks.count)
        case .backward:
            for block in order.postorder {
                boundaryStates[block.index] = start
            }
            pending = WorkQueue(order.postorder, blockCount: body.blocks.count)
        }
    }

    /// Carries each pending block's state through it to the blocks it flows into, until no boundary state changes.
    private mutating func settle() {
        while let block = pending.pop() {
            // A block that no state has reached yet has nothing to hand on.
            guard var state = boundaryStates[block.index] else { continue }
            state.apply(across: effects[block.index], in: function)

            // Each block the state flows into is pending again where the state adds to its own.
            for next in blocks(after: block) where merge(state, intoBoundaryOf: next) {
                pending.push(next)
            }
        }
    }

    /// The blocks that `block`'s state flows into: its successors going forward, and the reached blocks that lead
    /// to it going backward.
    private func blocks(after block: BlockID) -> [BlockID] {
        switch direction {
        case .forward: body.blocks[block.index].terminator.successors
        case .backward: order.predecessors[block.index]
        }
    }

    /// Merges `state` into the state at `block`'s boundary, and returns whether that changed it.
    private mutating func merge(_ state: State, intoBoundaryOf block: BlockID) -> Bool {
        guard let previous = boundaryStates[block.index] else {
            boundaryStates[block.index] = state
            return true
        }

        // A merge that dropped part of either state could swing back and forth forever, so it stops the solver
        // here, in debug builds, rather than there.
        let merged = previous.merged(with: state)
        assert(
            merged.merged(with: previous) == merged && merged.merged(with: state) == merged,
            "a dataflow merge must only grow a block's state",
        )

        guard merged != previous else { return false }
        boundaryStates[block.index] = merged
        return true
    }
}

/// Blocks waiting their turn, each at most once at a time, handed out earliest in the solver's order first.
private struct WorkQueue {
    private let order: [BlockID]
    /// The position in `order` of each block, indexed by `BlockID`; `outsideOrder` for a block it leaves out.
    private let positions: [Int]
    /// The positions of the waiting blocks, as a binary heap whose root is the earliest.
    private var heap: [Int]
    /// Whether the block at each position is waiting.
    private var isWaiting: [Bool]

    private static var outsideOrder: Int { -1 }

    /// A queue of `order`, every block of it waiting, from a function of `blockCount` blocks.
    init(_ order: [BlockID], blockCount: Int) {
        self.order = order
        var positions = Array(repeating: Self.outsideOrder, count: blockCount)
        for (position, block) in order.enumerated() {
            positions[block.index] = position
        }
        self.positions = positions
        // Positions in increasing order already form a heap.
        heap = Array(order.indices)
        isWaiting = Array(repeating: true, count: order.count)
    }

    /// Adds `block`, unless it is already waiting.
    mutating func push(_ block: BlockID) {
        let position = positions[block.index]
        precondition(position != Self.outsideOrder, "the solver hands on states only to blocks of its order")
        guard !isWaiting[position] else { return }
        isWaiting[position] = true

        // Sift the new position up past each parent that comes after it.
        var child = heap.count
        heap.append(position)
        while child > 0, heap[(child - 1) / 2] > heap[child] {
            heap.swapAt(child, (child - 1) / 2)
            child = (child - 1) / 2
        }
    }

    /// Takes the waiting block that comes first in the order, or returns nil when none is waiting.
    mutating func pop() -> BlockID? {
        guard let first = heap.first else { return nil }
        isWaiting[first] = false

        // Move the last position to the root, and sift it down past each child that comes before it.
        let last = heap.removeLast()
        if !heap.isEmpty {
            heap[0] = last
            var parent = 0
            while true {
                let left = 2 * parent + 1
                guard left < heap.count else { break }
                let right = left + 1
                let earlier = right < heap.count && heap[right] < heap[left] ? right : left
                guard heap[earlier] < heap[parent] else { break }
                heap.swapAt(parent, earlier)
                parent = earlier
            }
        }
        return order[first]
    }
}

/// The blocks of a function that some path from its entry reaches, in the orders a dataflow solver visits them.
private struct BlockOrder {
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

/// The reached blocks in the order a forward walk visits them: each after the blocks that lead to it, and each loop's
/// blocks together, header first, so the solver settles a loop before it carries the loop's state on.
private struct LoopNestOrder {
    private(set) var blocks: [BlockID] = []
    /// Indexed by `BlockID`.
    private let successors: [[BlockID]]
    /// The part being ordered that each block lies in, indexed by `BlockID`; a search keeps to one part. An unreached
    /// block lies in `unreached`, which no search orders.
    private var part: [Int]
    private var partCount = 1
    /// When the search of its part reached each block, indexed by `BlockID`; `unreached` where it hasn't yet.
    private var reachedAt: [Int]
    /// The earliest `reachedAt` that each block leads back to through `stack`, indexed by `BlockID`.
    private var earliestReachable: [Int]
    /// The reached blocks not yet in a component, in the order the search reached them.
    private var stack: [BlockID] = []
    private var isOnStack: [Bool]
    private var clock = 0

    private static var unreached: Int { -1 }

    /// The order of `reached`, the blocks of `body` that some path from its entry reaches, the entry first.
    init(_ body: IRBody, reached: [BlockID]) {
        successors = body.blocks.map(\.terminator.successors)
        part = Array(repeating: Self.unreached, count: body.blocks.count)
        reachedAt = Array(repeating: Self.unreached, count: body.blocks.count)
        earliestReachable = Array(repeating: 0, count: body.blocks.count)
        isOnStack = Array(repeating: false, count: body.blocks.count)
        for block in reached {
            part[block.index] = 0
        }
        order(reached, inPart: 0)
    }

    /// Adds `members`, the blocks of part `id`, to the order: each strongly connected component in turn, its header
    /// first, then the rest of it ordered the same way.
    private mutating func order(_ members: [BlockID], inPart id: Int) {
        for component in components(of: members, inPart: id) {
            let header = component[0]
            blocks.append(header)
            guard component.count > 1 else { continue }

            // The rest of the loop is a part of its own, which leaves out the edges back to the header.
            let inner = Array(component.dropFirst())
            let innerID = partCount
            partCount += 1
            for block in inner {
                part[block.index] = innerID
                reachedAt[block.index] = Self.unreached
            }
            order(inner, inPart: innerID)
        }
    }

    /// The strongly connected components of part `id`, in the order their edges run, each in the order it was reached.
    private mutating func components(of members: [BlockID], inPart id: Int) -> [[BlockID]] {
        var found: [[BlockID]] = []
        for root in members where reachedAt[root.index] == Self.unreached {
            search(from: root, inPart: id, into: &found)
        }
        // A search finds each component after every component its edges lead to.
        return found.reversed()
    }

    /// Adds the strongly connected components that a depth-first search of part `id` from `root` finds to `found`, by
    /// Tarjan's algorithm.
    private mutating func search(from root: BlockID, inPart id: Int, into found: inout [[BlockID]]) {
        reach(root)
        var path: [(block: BlockID, followed: Int)] = [(root, 0)]
        while let (block, followed) = path.last {
            let next = successors[block.index]
            if followed < next.count {
                path[path.count - 1].followed += 1
                let successor = next[followed]
                // An edge out of the part, such as one back to the loop's header, is left out.
                guard part[successor.index] == id else { continue }
                if reachedAt[successor.index] == Self.unreached {
                    reach(successor)
                    path.append((successor, 0))
                } else if isOnStack[successor.index] {
                    // An edge to a block on the stack leads back to it.
                    lowerEarliest(of: block, to: reachedAt[successor.index])
                }
                continue
            }

            // With every successor followed, the block before it on the path leads back as far as it does.
            path.removeLast()
            if let (parent, _) = path.last { lowerEarliest(of: parent, to: earliestReachable[block.index]) }
            // A block that leads back to nothing reached before it begins a component.
            if earliestReachable[block.index] == reachedAt[block.index] { found.append(popComponent(from: block)) }
        }
    }

    private mutating func reach(_ block: BlockID) {
        reachedAt[block.index] = clock
        earliestReachable[block.index] = clock
        clock += 1
        stack.append(block)
        isOnStack[block.index] = true
    }

    private mutating func lowerEarliest(of block: BlockID, to time: Int) {
        earliestReachable[block.index] = min(earliestReachable[block.index], time)
    }

    /// Takes the component that `first` begins off the stack.
    private mutating func popComponent(from first: BlockID) -> [BlockID] {
        guard let start = stack.lastIndex(of: first) else {
            preconditionFailure("a search puts each block it reaches on the stack")
        }
        let component = Array(stack[start...])
        stack.removeSubrange(start...)
        for block in component {
            isOnStack[block.index] = false
        }
        return component
    }
}
