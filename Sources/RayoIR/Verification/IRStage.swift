/// The stage that gave a program its IR, which decides what the verifier asks of its accesses and its locals' lives.
public enum IRStage: Sendable {
    /// Lowering, which begins each access and leaves its end to the ownership stage, and declares each local and leaves
    /// its retirement to the ownership stage too.
    case lowering
    /// The ownership stage, which writes the end of each access and the retirement of each local, so that the IR it
    /// gives ends each access once on every path from where it begins, and uses none after its end, and uses no local
    /// on any path after its retirement until a declaration starts its life again.
    case ownership
}
