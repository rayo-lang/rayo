/// The settled states of a dataflow analysis through a function. They answer what the state is at each point of a
/// block: point `i` lies just before the statement at `i`, the point at the number of statements just before the
/// terminator, and the point one past that just after it.
package struct DataflowResults<State: DataflowState> {
    private let effects: BodyEffects
    /// What the state needs to know of the function.
    private let function: State.Function
    /// The settled state at each block's boundary, indexed by `BlockID`: at its entry going forward, and at its exit
    /// going backward. It is nil for a block that no path from the entry reaches.
    private let boundaryStates: [State?]

    init(effects: BodyEffects, function: State.Function, boundaryStates: [State?]) {
        self.effects = effects
        self.function = function
        self.boundaryStates = boundaryStates
    }

    /// The settled state at `block`'s boundary: at its entry going forward, and at its exit going backward; nil where
    /// no state reaches the block.
    package func boundaryState(of block: BlockID) -> State? {
        boundaryStates[block.index]
    }

    /// Walks `block` from its boundary in the analysis's direction, and lends `visit` the state at each point in turn,
    /// with the point. Returns whether a state reaches the block; where none does, it visits no point.
    ///
    /// The walk changes one state in place as it crosses each statement. A `visit` that keeps the state itself makes
    /// the next statement copy the whole of it, so a check keeps only what it works out from each state.
    @discardableResult
    package func walk(_ block: BlockID, visit: (_ point: Int, _ state: State) -> Void) -> Bool {
        guard var state = boundaryStates[block.index] else { return false }
        // The statements, then the terminator, each crossed from the point before it to the point after it.
        let crossings = effects[block]

        switch state.direction {
        case .forward:
            for index in crossings.indices {
                visit(index, state)
                state.apply(crossings[index], in: function)
            }
            visit(crossings.count, state)

        case .backward:
            for index in crossings.indices.reversed() {
                visit(index + 1, state)
                state.apply(crossings[index], in: function)
            }
            visit(0, state)
        }
        return true
    }

    /// Walks `block` from its boundary in the analysis's direction, and lends `visit` each effect in turn, with the
    /// state just before the walk crosses it. Returns whether a state reaches the block; stops where `visit` throws.
    @discardableResult
    package func walkEffects<Failure: Error>(
        of block: BlockID, visit: (_ effect: Effect, _ state: State) throws(Failure) -> Void,
    ) throws(Failure) -> Bool {
        guard var state = boundaryStates[block.index] else { return false }
        let crossings = effects[block].all

        switch state.direction {
        case .forward:
            for effect in crossings {
                try visit(effect, state)
                state.apply(effect, in: function)
            }
        case .backward:
            for effect in crossings.reversed() {
                try visit(effect, state)
                state.apply(effect, in: function)
            }
        }
        return true
    }

    /// Walks `block` from its boundary in the analysis's direction, and lends `visit` the state before the block's
    /// first effect and after each of its effects in turn, with the number of its effects that come before the state.
    /// Returns whether a state reaches the block; where none does, it visits nothing.
    @discardableResult
    package func walkBetweenEffects(
        of block: BlockID, visit: (_ effectsBefore: Int, _ state: State) -> Void,
    ) -> Bool {
        guard var state = boundaryStates[block.index] else { return false }
        let crossings = effects[block].all

        switch state.direction {
        case .forward:
            var effectsBefore = 0
            for effect in crossings {
                visit(effectsBefore, state)
                state.apply(effect, in: function)
                effectsBefore += 1
            }
            visit(effectsBefore, state)

        case .backward:
            var effectsBefore = crossings.count
            for effect in crossings.reversed() {
                visit(effectsBefore, state)
                state.apply(effect, in: function)
                effectsBefore -= 1
            }
            visit(effectsBefore, state)
        }
        return true
    }
}
