import RayoIR

/// What each local of a function, and each place moved out of one, holds at each point, carried forward from the
/// function's entry.
struct InitializationAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.forward
    let startState: InitializationState

    /// The analysis of `body`.
    init(_ body: IRBody) {
        startState = InitializationState(entering: body)
    }

    func apply(_ statement: Statement, to state: inout InitializationState) {
        state.apply(statement)
    }

    func apply(_ terminator: Terminator, to state: inout InitializationState) {
        state.apply(terminator)
    }
}
