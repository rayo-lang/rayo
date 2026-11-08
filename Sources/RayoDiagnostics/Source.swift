/// A position in a source file: 1-based line and column, and the 0-based byte offset.
public struct SourceLocation: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var line: Int
    public var column: Int
    public var offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }

    public static func < (a: SourceLocation, b: SourceLocation) -> Bool { a.offset < b.offset }

    public var description: String { "\(line):\(column)" }
}

/// The half-open span of source text a token or a syntax node covers.
public struct SourceRange: Sendable, Hashable, CustomStringConvertible {
    public var start: SourceLocation
    public var end: SourceLocation

    public init(_ start: SourceLocation, _ end: SourceLocation) {
        self.start = start
        self.end = end
    }

    public func to(_ other: SourceRange) -> SourceRange { SourceRange(start, other.end) }

    public var description: String { start.description }
}

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
