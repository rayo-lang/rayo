public import RayoSource

/// A parsed file: its declarations, and the source they were parsed from.
public struct SourceFile: Sendable {
    /// The file's top-level declarations, in source order, those that failed to parse among them.
    public var declarations: [Declaration]
    /// The source, as UTF-8.
    public let source: [UInt8]

    public init(declarations: [Declaration], source: [UInt8]) {
        self.declarations = declarations
        self.source = source
    }

    /// The text of the source that `range` covers, such as a call an error names as the source writes it.
    public func text(of range: SourceRange) -> String {
        String(decoding: source[range.start.offset..<range.end.offset], as: UTF8.self)
    }
}
