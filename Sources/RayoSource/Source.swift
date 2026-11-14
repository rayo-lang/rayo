/// A position in a source file: 1-based line and column, and the 0-based byte offset.
///
/// Two positions are the same where their lines and columns are, and come in the order those do, since within one
/// file the line and column decide the offset. A position known only by its line and column, such as one read back
/// from text that names no offsets, has the offset 0, and is still the same position as the one the lexer found there.
public struct SourceLocation: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var line: Int
    public var column: Int
    public var offset: Int

    public init(line: Int, column: Int, offset: Int) {
        self.line = line
        self.column = column
        self.offset = offset
    }

    public static func == (a: SourceLocation, b: SourceLocation) -> Bool {
        (a.line, a.column) == (b.line, b.column)
    }

    public static func < (a: SourceLocation, b: SourceLocation) -> Bool {
        (a.line, a.column) < (b.line, b.column)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(line)
        hasher.combine(column)
    }

    public var description: String { "\(line):\(column)" }
}

/// A half-open span of source text.
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
