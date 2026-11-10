import RayoSema
import RayoSource

/// A local that an operand or a statement's destination names, and where the source names it, which is where an
/// error about it points.
public struct Place: Sendable {
    public var local: LocalID
    public var range: SourceRange

    public init(local: LocalID, range: SourceRange) {
        self.local = local
        self.range = range
    }
}
