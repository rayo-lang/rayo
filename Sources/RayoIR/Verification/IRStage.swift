/// The stage that gave a program its IR, which decides what the verifier asks of its accesses.
public enum IRStage: Sendable {
    /// Lowering, which begins each access and leaves its end to the ownership stage.
    case lowering
    /// The ownership stage, which writes the end of each access, so that the IR it gives ends each access once on
    /// every path from where it begins, and uses none after its end.
    case ownership
}
