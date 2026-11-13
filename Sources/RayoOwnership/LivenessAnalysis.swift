import RayoIR

/// Which locals of a function, and which fields inside them, hold a value that some code reads later, at each point,
/// carried backward from the function's exits.
struct LivenessAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.backward
    let startState = LivenessState()
    let places: PlaceTypes

    func apply(_ statement: Statement, to state: inout LivenessState) {
        state.apply(backwardsThrough: statement, in: places)
    }

    func apply(_ terminator: Terminator, to state: inout LivenessState) {
        state.apply(backwardsThrough: terminator)
    }
}
