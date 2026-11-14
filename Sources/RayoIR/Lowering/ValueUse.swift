/// What a position does with the value that stands in it, which decides whether a place written on its own there is
/// read or moved.
enum ValueUse {
    /// Reads the value, as an argument, an operand or a condition does, so the place keeps it.
    case read
    /// Takes the value, as a declaration, an assignment, a `return`, `_ =` or a struct's field does, so the place
    /// gives it up.
    case take
}
