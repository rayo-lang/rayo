import RayoIR

/// The settled states of a dataflow analysis through a function. They answer what the state is at each point of a
/// block: point `i` lies just before the statement at `i`, the point at the number of statements just before the
/// terminator, and the point one past that just after it.
struct DataflowResults<State: DataflowState> {
    /// The effects of each block's statements and terminator, indexed by `BlockID`, as `BasicBlock.effects` gives them.
    private let effects: [[[Effect]]]
    /// What the state needs to know of the function.
    private let function: State.Function
    /// The settled state at each block's boundary, indexed by `BlockID`: at its entry going forward, and at its exit
    /// going backward. It is nil for a block that no path from the entry reaches.
    private let boundaryStates: [State?]

    init(effects: [[[Effect]]], function: State.Function, boundaryStates: [State?]) {
        self.effects = effects
        self.function = function
        self.boundaryStates = boundaryStates
    }

    /// The settled state at `block`'s boundary: at its entry going forward, and at its exit going backward; nil where
    /// no state reaches the block.
    func boundaryState(of block: BlockID) -> State? {
        boundaryStates[block.index]
    }

    /// Walks `block` from its boundary in the analysis's direction, and lends `visit` the state at each point in turn,
    /// with the point. Returns whether a state reaches the block; where none does, it visits no point.
    ///
    /// The walk changes one state in place as it crosses each statement. A `visit` that keeps the state itself makes
    /// the next statement copy the whole of it, so a check keeps only what it works out from each state.
    @discardableResult
    func walk(_ block: BlockID, visit: (_ point: Int, _ state: State) -> Void) -> Bool {
        guard var state = boundaryStates[block.index] else { return false }
        // The statements, then the terminator, each crossed from the point before it to the point after it.
        let crossings = effects[block.index]

        switch state.direction {
        case .forward:
            for (index, crossing) in crossings.enumerated() {
                visit(index, state)
                state.apply(crossing, in: function)
            }
            visit(crossings.count, state)

        case .backward:
            for (index, crossing) in crossings.enumerated().reversed() {
                visit(index + 1, state)
                state.apply(crossing, in: function)
            }
            visit(0, state)
        }
        return true
    }
}
