import RayoSource

/// The place a statement stores its value in, and where the source names it.
public struct Destination: Equatable, Sendable {
    public var place: Place
    public var range: SourceRange

    public init(_ place: Place, at range: SourceRange) {
        self.place = place
        self.range = range
    }
}
