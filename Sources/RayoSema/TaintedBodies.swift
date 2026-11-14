/// The function bodies of a check that are tainted, and so have no body in the checked program.
///
/// A body is tainted when checking it reports an error, holds a statement that failed to parse, or reaches a
/// declaration that failed, whose error was reported there. A tainted body may report no error of its own, so its
/// taint is recorded as it is checked.
final class TaintedBodies {
    /// The functions whose bodies are tainted.
    private(set) var functions: Set<FunctionID> = []
    /// The functions whose bodies are being checked, innermost last. A body is checked while another is when a call
    /// in the other needs its result type.
    private var checking: [FunctionID] = []

    /// Taints the body being checked. Outside a body, a declaration that reaches a failed one fails in its own way,
    /// so this does nothing.
    func taint() {
        if let body = checking.last { functions.insert(body) }
    }

    /// Gives what `check` gives, as the body of the function `id` is checked, so that what it taints is that body.
    func checkingBody<Checked>(of id: FunctionID, _ check: () -> Checked) -> Checked {
        checking.append(id)
        defer { checking.removeLast() }
        return check()
    }
}
