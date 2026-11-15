import RayoDiagnostics
import RayoSource

/// Collects the errors and warnings of a check. Every function body of a file reports into one list, also a body
/// checked while another is, for a call that needs its result type.
final class ErrorList {
    private(set) var list: [Diagnostic] = []
    /// The bodies the check finds tainted, among them each body that reports an error here that leaves it without a
    /// meaning.
    let taints = TaintedBodies()

    /// Reports `code` at `range`. An error taints the body being checked; a warning flags code that still has a
    /// meaning, so it taints nothing.
    func report(_ code: ErrorCode, at range: SourceRange) {
        list.append(Diagnostic(code, at: range))
        if code.severity == .error { taints.taint() }
    }

    /// Reports `code` at `range`, an error in code the checker still gives a meaning, such as a value no code uses,
    /// which it drops as `_ =` would. The body keeps its meaning, so it isn't tainted, and the stages after checking
    /// still report the errors they find in it.
    func reportKeepingMeaning(_ code: ErrorCode, at range: SourceRange) {
        list.append(Diagnostic(code, at: range))
    }
}
