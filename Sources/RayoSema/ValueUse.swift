/// What a position does with the value that stands in it.
enum ValueUse {
    /// Reads the value, such as an argument or an operand, so a local written bare keeps it.
    case read
    /// Takes the value, as a declaration, an assignment, a `return`, `_ =` or a struct's initializer does, so a local
    /// or a field written bare is moved.
    case take
}
