/// Carries a dataflow analysis's state through a function's blocks until the state at each block's boundary settles:
/// at its entry going forward, and at its exit going backward.
package struct DataflowSolver<State: DataflowState> {
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
    package static func solve(
        from start: State, through body: IRBody, knowing function: State.Function,
    ) -> DataflowResults<State> {
        var solver = DataflowSolver(from: start, through: body, knowing: function)
        solver.settle { _, state, effects in state.apply(across: effects, in: function) }
        return DataflowResults(effects: solver.effects, function: function, boundaryStates: solver.boundaryStates)
    }

    /// Carries the state through `body` as `solve(from:through:knowing:)` does, but has `cross` take it across each
    /// block, given the block and its effects, as `apply(across:in:)` would. The last time `cross` crosses a block, the
    /// state is the one the block settles on, since a block whose boundary state changes waits to be crossed again.
    package static func solve(
        from start: State, through body: IRBody, knowing function: State.Function,
        crossingEachBlock cross: (BlockID, inout State, [[Effect]]) -> Void,
    ) {
        var solver = DataflowSolver(from: start, through: body, knowing: function)
        solver.settle(crossingEachBlock: cross)
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
            let forwardOrder = LoopNestOrder(order)
            pending = WorkQueue(forwardOrder.blocks, blockCount: body.blocks.count)
        case .backward:
            for block in order.postorder {
                boundaryStates[block.index] = start
            }
            pending = WorkQueue(order.postorder, blockCount: body.blocks.count)
        }
    }

    /// Carries each pending block's state through it with `cross` to the blocks it flows into, until no boundary state
    /// changes.
    private mutating func settle(crossingEachBlock cross: (BlockID, inout State, [[Effect]]) -> Void) {
        while let block = pending.pop() {
            // A block that no state has reached yet has nothing to hand on.
            guard var state = boundaryStates[block.index] else { continue }
            cross(block, &state, effects[block.index])

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

/// The blocks of a function that some path from its entry reaches, in the orders a depth-first walk from the entry
/// reaches and leaves them. It records where the walk reached each block, so whether one block lies below another in
/// the walk is a lookup.
private struct BlockOrder {
    /// The reached blocks, each after the blocks it leads to, except along an edge back to a block whose walk is
    /// still under way, such as a loop's header.
    private(set) var postorder: [BlockID] = []
    /// The reached blocks in the order the walk reaches them.
    private(set) var preorder: [BlockID] = []
    /// The reached blocks that lead to each block, indexed by `BlockID`.
    private(set) var predecessors: [[BlockID]]
    /// The position of each block in `preorder`, indexed by `BlockID`; `unreached` for a block no path reaches.
    private var reachedAt: [Int]
    /// The position in `preorder` of the last block the walk reached from each block, indexed by `BlockID`. The
    /// blocks it reached from a block are those after it in `preorder`, up to and including that one.
    private var lastReachedFrom: [Int]

    private static var unreached: Int { -1 }

    init(_ body: IRBody) {
        predecessors = Array(repeating: [], count: body.blocks.count)
        reachedAt = Array(repeating: Self.unreached, count: body.blocks.count)
        lastReachedFrom = Array(repeating: Self.unreached, count: body.blocks.count)

        // Walk depth first from the entry, holding the path walked so far and how many of each block's successors
        // it has followed. A block joins the postorder once all its successors are followed.
        var path: [(block: BlockID, followed: Int)] = []
        reach(BlockID(index: 0), from: &path)
        while let (block, followed) = path.last {
            let successors = body.blocks[block.index].terminator.successors
            guard followed < successors.count else {
                lastReachedFrom[block.index] = preorder.count - 1
                postorder.append(block)
                path.removeLast()
                continue
            }

            // Follow the next successor, and walk on from it the first time it is reached.
            path[path.count - 1].followed += 1
            let successor = successors[followed]
            predecessors[successor.index].append(block)
            guard reachedAt[successor.index] == Self.unreached else { continue }
            reach(successor, from: &path)
        }
    }

    /// How many blocks the function has, reached or not.
    var blockCount: Int { predecessors.count }

    /// Whether the walk reached `block` while it walked on from `ancestor`, so `ancestor` lies on the walk's path to
    /// `block`. A block is its own ancestor.
    func isAncestor(_ ancestor: BlockID, of block: BlockID) -> Bool {
        let position = reachedAt[block.index]
        return reachedAt[ancestor.index] <= position && position <= lastReachedFrom[ancestor.index]
    }

    /// Reaches `block`, and walks on from it at the end of `path`.
    private mutating func reach(_ block: BlockID, from path: inout [(block: BlockID, followed: Int)]) {
        reachedAt[block.index] = preorder.count
        preorder.append(block)
        path.append((block, 0))
    }
}

/// The reached blocks in the order a forward walk visits them: each after the blocks that lead to it, and each loop's
/// blocks together, header first, so the solver settles a loop before it carries the loop's state on. It takes time
/// about linear in the function, however deep its loops nest.
private struct LoopNestOrder {
    private(set) var blocks: [BlockID] = []

    /// The order of the blocks that `order` reached.
    init(_ order: BlockOrder) {
        let loops = InnermostLoops(order)
        let blockCount = order.blockCount

        // Each loop's blocks, and at `blockCount` the blocks in no loop, in reverse postorder, which puts each block
        // after those that lead to it, leaving out the edges back to a loop's header.
        var members = Array(repeating: [BlockID](), count: blockCount + 1)
        for block in order.postorder.reversed() {
            members[loops.header[block.index]?.index ?? blockCount].append(block)
        }

        // Add the members of each loop in turn, from the blocks in no loop out, putting each loop's members in place
        // of its header, right after it.
        var pending: [(loop: Int, next: Int)] = [(blockCount, 0)]
        while let (loop, next) = pending.last {
            guard next < members[loop].count else {
                pending.removeLast()
                continue
            }
            pending[pending.count - 1].next += 1
            let block = members[loop][next]
            blocks.append(block)
            if loops.isHeader[block.index] { pending.append((block.index, 0)) }
        }
    }
}

/// The innermost loop around each reached block, found by Havlak's algorithm. It visits blocks from the last reached to
/// the first: one that an edge from below it leads back to heads a loop, which takes in every block that reaches that
/// edge without passing the header. A loop found already is taken in whole, which keeps the cost about linear.
private struct InnermostLoops {
    /// The header of the innermost loop around each block, indexed by `BlockID`, or nil for a block in no loop. A
    /// header's is the header of the loop around its own.
    private(set) var header: [BlockID?]
    /// Whether each block heads a loop, indexed by `BlockID`.
    private(set) var isHeader: [Bool]
    /// The block that stands for each block's outermost loop found so far, indexed by `BlockID`: itself until a loop
    /// takes it in, and otherwise the next block on the way to that loop's header.
    private var outermost: [BlockID]
    /// The edges into each block from blocks the walk didn't reach from it, indexed by `BlockID`. A loop that a path
    /// enters past its header has each such edge taken as one into the header.
    private var entries: [[BlockID]]

    init(_ order: BlockOrder) {
        let blockCount = order.blockCount
        header = Array(repeating: nil, count: blockCount)
        isHeader = Array(repeating: false, count: blockCount)
        outermost = (0..<blockCount).map { BlockID(index: $0) }
        entries = Array(repeating: [], count: blockCount)
        for block in order.preorder {
            entries[block.index] = order.predecessors[block.index].filter { !order.isAncestor(block, of: $0) }
        }

        for block in order.preorder.reversed() {
            takeInLoop(headedBy: block, in: order)
        }
    }

    /// Takes the blocks of the loop that `candidate` heads into it, where an edge leads back to `candidate`, and marks
    /// `candidate` as a header. Each loop found already joins whole, through its outermost header.
    private mutating func takeInLoop(headedBy candidate: BlockID, in order: BlockOrder) {
        var members: [BlockID] = []
        var isMember: Set<Int> = []

        // The blocks that edges back to the candidate come from begin the loop.
        for source in order.predecessors[candidate.index] where order.isAncestor(candidate, of: source) {
            isHeader[candidate.index] = true
            let member = outermostLoop(of: source)
            if member != candidate, isMember.insert(member.index).inserted { members.append(member) }
        }

        // The loop takes in each block that leads into a block of it, up to the header.
        var next = 0
        while next < members.count {
            let member = members[next]
            next += 1
            for entry in entries[member.index] {
                let outside = outermostLoop(of: entry)
                // A block the walk didn't reach from the header enters the loop past it, so the edge is taken as one
                // into the header, and the block stays outside the loop.
                guard order.isAncestor(candidate, of: outside) else {
                    entries[candidate.index].append(outside)
                    continue
                }
                if outside != candidate, isMember.insert(outside.index).inserted { members.append(outside) }
            }
        }

        // Each member's innermost loop is this one, and the loop stands for the member from now on.
        for member in members {
            header[member.index] = candidate
            outermost[member.index] = candidate
        }
    }

    /// The header of the outermost loop found so far that `block` lies in, or `block` itself where it lies in none.
    /// Each block on the way is set to point straight at it, so the next search for any of them is short.
    private mutating func outermostLoop(of block: BlockID) -> BlockID {
        var root = block
        while outermost[root.index] != root {
            root = outermost[root.index]
        }

        var current = block
        while outermost[current.index] != root {
            let next = outermost[current.index]
            outermost[current.index] = root
            current = next
        }
        return root
    }
}
