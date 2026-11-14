import RayoIR

/// Which accesses of a function some path to each point has not begun, carried forward from the function's entry.
struct UnbegunAccessAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.forward
    let startState: UnbegunAccessState

    /// The analysis of `body`, none of whose accesses has begun on entry.
    init(_ body: IRBody) {
        startState = UnbegunAccessState(Set(body.begunAccesses.keys))
    }

    func apply(_ statement: Statement, to state: inout UnbegunAccessState) {
        state.apply(statement)
    }

    /// A terminator begins no access.
    func apply(_ terminator: Terminator, to state: inout UnbegunAccessState) {}
}
