import RayoSource

/// A step from a place to a part of the value it holds.
public enum CheckedPlaceStep: Sendable {
    /// Steps into a struct's field, by its place in its struct's declaration. The source names the place the step
    /// leads to at `range`, from the root through the field's name.
    case field(Int, range: SourceRange)
}
