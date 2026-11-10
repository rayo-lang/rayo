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
