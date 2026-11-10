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
