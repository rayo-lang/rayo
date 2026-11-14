/// What a position does with the value that stands in it, which decides whether a place written on its own there is
/// read or moved.
enum ValueUse {
    /// Reads the value, as a function's argument, an operand or a condition does, so the place keeps it.
    case read
    /// Takes the value, as a declaration, an assignment, a `return`, `_ =`, a primary initializer's argument or an
    /// array literal's element does, so the place gives it up.
    case take
}
