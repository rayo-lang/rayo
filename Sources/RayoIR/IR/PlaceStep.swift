/// A step from a place to a part of the value it holds. Steps into fields order as the fields' declarations do.
public enum PlaceStep: Hashable, Comparable, Sendable {
    /// Steps into a struct's field, by its place in its struct's declaration.
    case field(Int)
}
