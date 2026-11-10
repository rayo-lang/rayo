import RayoSource

/// An error in a program, and where it is.
public struct Diagnostic: Sendable, Hashable, CustomStringConvertible {
    public var code: ErrorCode
    public var range: SourceRange

    public init(_ code: ErrorCode, at range: SourceRange) {
        self.code = code
        self.range = range
    }

    public var description: String { "\(range.start): error[\(code.identifier)]: \(code.message)" }
}

extension Array where Element == Diagnostic {
    /// The diagnostics by where they start in the source, those that start at one place in the order they come in.
    public var inSourceOrder: [Diagnostic] {
        enumerated().sorted { a, b in
            (a.element.range.start, a.offset) < (b.element.range.start, b.offset)
        }.map(\.element)
    }
}
