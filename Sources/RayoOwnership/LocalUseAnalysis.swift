import RayoIR

/// Which locals of a function some later code uses before a declaration starts their lives again, at each point,
/// carried backward from the function's exits.
struct LocalUseAnalysis: DataflowAnalysis {
    let direction = DataflowDirection.backward
    let startState = LocalUseState()
    /// The locals each statement and terminator of the function uses.
    let uses: LocalUses

    func apply(_ statement: Statement, to state: inout LocalUseState) {
        state.apply(backwardsThrough: statement, using: uses)
    }

    func apply(_ terminator: Terminator, to state: inout LocalUseState) {
        state.apply(backwardsThrough: terminator, using: uses)
    }
}
