import RayoSema
import RayoSource

/// A local, or a field inside it, that an operand or a statement's destination names, and where the source names it,
/// which is where an error about it points.
public struct Place: Equatable, Sendable {
    public var local: LocalID
    /// The fields that lead from the local to the place, outermost first, each by its place in its struct's
    /// declaration; none where the place is the whole local.
    public var fields: [Int]
    public var range: SourceRange

    public init(local: LocalID, fields: [Int] = [], range: SourceRange) {
        self.local = local
        self.fields = fields
        self.range = range
    }
}
