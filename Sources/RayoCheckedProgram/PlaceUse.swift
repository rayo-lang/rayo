/// What a position does with a place that the source writes there bare, which semantic checking decides.
public enum PlaceUse: Hashable, Sendable {
    /// Takes a copy of the place's value, which is implicitly copyable, so the place keeps it.
    case copy
    /// Takes the value, so the place holds none until it is assigned again.
    case move
    /// Reads the value where the place holds it, for as long as the position uses it, so the place keeps it: a
    /// borrowing parameter's argument, or a value that is only read.
    case lend
    /// Refers to the place, as a `ref let` does: the local reads it through an access, so the place keeps its value,
    /// and can't change or move while the local is used.
    case borrow
}
