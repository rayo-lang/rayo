import RayoSource

/// What an access does, to which place, and where the source names the place.
public struct Access: Equatable, Sendable {
    public var kind: AccessKind
    public var place: Place
    public var range: SourceRange

    public init(_ kind: AccessKind, to place: Place, at range: SourceRange) {
        self.kind = kind
        self.place = place
        self.range = range
    }
}

/// What an access may do with the place it reaches, which decides the other accesses it conflicts with. Its raw
/// value is its name in the IR's text.
public enum AccessKind: String, Hashable, Sendable {
    /// Reads the place and changes nothing, as a borrowed argument does. Other reads may overlap it.
    case read
    /// May change the place, as a `mutable` argument does. No other access may overlap it.
    case modify
}
