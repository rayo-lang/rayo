/// A half-open span of source text.
public struct SourceRange: Sendable, Hashable, CustomStringConvertible {
    public var start: SourceLocation
    public var end: SourceLocation

    public init(_ start: SourceLocation, _ end: SourceLocation) {
        self.start = start
        self.end = end
    }

    /// The range from this one's start to `other`'s end.
    public func to(_ other: SourceRange) -> SourceRange { SourceRange(start, other.end) }

    public var description: String { start.description }
}

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
