import RayoSource

/// What an access does, to which place, and where the source names the place.
public struct Access: Equatable, Sendable {
    public var kind: AccessKind
    public var enforcement: Enforcement
    public var place: Place
    public var range: SourceRange

    public init(_ kind: AccessKind, _ enforcement: Enforcement, to place: Place, at range: SourceRange) {
        self.kind = kind
        self.enforcement = enforcement
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

/// How the program makes sure that no access conflicts with another while it is live. Its raw value is its name in
/// the IR's text.
public enum Enforcement: String, Hashable, Sendable {
    /// The compiler proves it, so the access costs nothing when the program runs.
    case `static`
    /// The access takes a mark on its place when it begins and releases it when it ends, and an access that conflicts
    /// with a mark panics. Only an object's value takes one, since code the compiler can't see may reach an object.
    case dynamic
}
