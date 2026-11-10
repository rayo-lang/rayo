import RayoDiagnostics
import RayoSource

/// The errors a check of a file finds, in the order they are reported. It is a class so that a body checked while
/// another is, for a call that needs its result type, reports into the same list.
final class ErrorList {
    private(set) var list: [Diagnostic] = []

    func report(_ code: ErrorCode, at range: SourceRange) {
        list.append(Diagnostic(code, at: range))
    }
}
