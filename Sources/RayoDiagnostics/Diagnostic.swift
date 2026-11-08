import RayoSource

public enum Severity: Sendable, Hashable {
    case error
    case note
}

public struct Diagnostic: Sendable, Hashable, CustomStringConvertible {
    public var severity: Severity
    public var message: String
    public var range: SourceRange

    public init(_ severity: Severity, _ message: String, at range: SourceRange) {
        self.severity = severity
        self.message = message
        self.range = range
    }

    public static func error(_ message: String, at range: SourceRange) -> Diagnostic {
        Diagnostic(.error, message, at: range)
    }

    public var description: String {
        let label = severity == .error ? "error" : "note"
        return "\(range.start): \(label): \(message)"
    }
}
