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
