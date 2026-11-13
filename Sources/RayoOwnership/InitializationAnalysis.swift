import RayoIR

/// What each local of a function, and each place moved out of one, holds at each point, carried forward from the
/// function's entry.
struct InitializationAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.forward
    let startState: InitializationState

    /// The analysis of `body`, whose first `parameterCount` locals are its function's parameters.
    init(_ body: IRBody, parameterCount: Int) {
        startState = InitializationState(entering: body, parameterCount: parameterCount)
    }

    func apply(_ statement: Statement, to state: inout InitializationState) {
        state.apply(statement)
    }

    func apply(_ terminator: Terminator, to state: inout InitializationState) {
        state.apply(terminator)
    }
}
