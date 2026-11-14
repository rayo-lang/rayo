import RayoIR

/// Which accesses and values of a function some later code uses, at each point, carried backward from the function's
/// exits.
struct AccessUseAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.backward
    let startState = AccessUseState()
    let places: PlaceTypes

    func apply(_ statement: Statement, to state: inout AccessUseState) {
        state.apply(backwardsThrough: statement, in: places)
    }

    func apply(_ terminator: Terminator, to state: inout AccessUseState) {
        state.apply(backwardsThrough: terminator)
    }
}
