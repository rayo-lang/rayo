import RayoIR

/// Which accesses the value of each local of a function depends on at each point, carried forward from the function's
/// entry.
struct DependencyAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.forward
    let startState = DependencyState()

    func apply(_ statement: Statement, to state: inout DependencyState) {
        state.apply(statement)
    }

    /// A terminator makes no value, so it changes no dependency.
    func apply(_ terminator: Terminator, to state: inout DependencyState) {}
}
