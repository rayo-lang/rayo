import RayoIR

/// The forward data flow of what each local of a function holds, through the function's control-flow graph.
struct InitializationAnalysis {
    /// The state on entry to each block, indexed by `BlockID`; nil for a block that no path from the function's
    /// entry reaches.
    private(set) var entryStates: [InitializationState?]

    /// A state that reaches the entry of `block`, from the function's entry or along an edge.
    private typealias Arrival = (block: BlockID, state: InitializationState)

    /// The analysis of `body`, whose first `parameterCount` locals are its function's parameters.
    init(_ body: IRBody, parameterCount: Int) {
        entryStates = Array(repeating: nil, count: body.blocks.count)
        let entry = InitializationState(entering: body, parameterCount: parameterCount)
        var pending: [Arrival] = [(BlockID(index: 0), entry)]
        while let arrival = pending.popLast() {
            pending += flow(arrival, through: body)
        }
    }

    /// Joins `arrival`'s state into the state on entry to its block. When that changes it, returns what the block
    /// hands each of its successors; otherwise none.
    private mutating func flow(_ arrival: Arrival, through body: IRBody) -> [Arrival] {
        // A state that adds nothing to what the block was entered with already changes nothing after it.
        guard let entryState = join(arrival.state, intoEntryOf: arrival.block) else { return [] }
        let block = body.blocks[arrival.block.index]
        var exitState = entryState
        exitState.apply(block)
        return block.terminator.successors.map { ($0, exitState) }
    }

    /// Joins `state` into the state on entry to `block`, and returns the joined state, or nil when that changed
    /// nothing.
    private mutating func join(_ state: InitializationState, intoEntryOf block: BlockID) -> InitializationState? {
        let joined = entryStates[block.index].map { $0.joined(with: state) } ?? state
        // A state the block was already entered with gives its successors nothing new.
        guard joined != entryStates[block.index] else { return nil }
        entryStates[block.index] = joined
        return joined
    }
}
