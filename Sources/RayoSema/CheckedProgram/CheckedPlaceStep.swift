import RayoSource

/// A step from a place to a part of the value it holds.
public enum CheckedPlaceStep: Sendable {
    /// Steps into a struct's field, by its place in its struct's declaration. The source names the place the step
    /// leads to at `range`, from the root through the field's name.
    case field(Int, range: SourceRange)
    /// Steps into an array's element, at the index a UInt value gives, which must lie below the array's count. A UInt
    /// literal index always does, since checking reports one that doesn't. The source names the place the step leads
    /// to at `range`, from the root through the `]`.
    case element(index: CheckedExpr, count: Int, range: SourceRange)
}
