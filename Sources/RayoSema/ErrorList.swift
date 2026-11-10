import RayoDiagnostics
import RayoSource

/// Collects the errors of a check. Every function body of a file reports into one list, also a body checked
/// while another is, for a call that needs its result type.
final class ErrorList {
    private(set) var list: [Diagnostic] = []

    func report(_ code: ErrorCode, at range: SourceRange) {
        list.append(Diagnostic(code, at: range))
    }
}
