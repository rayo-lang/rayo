/// What a position does with the value that stands in it, which decides whether a place written on its own there is
/// read, moved or borrowed.
enum ValueUse {
    /// Reads the value, as a borrowed argument, an operand, a condition or the value an array is filled with does, so
    /// the place keeps it.
    case read
    /// Takes the value, as a declaration of a `let` or `var`, an assignment, a `return`, `_ =`, an owned
    /// argument or an array literal's element does, so the place gives it up. A value of an implicitly copyable type
    /// is copied instead, so the place keeps it.
    case take
    /// Borrows the value, as the declaration of a `ref let` does: a place that a local holds is read through an
    /// access that the local's value then depends on, so the place keeps its value, and can't change or move while
    /// the local is used. Any other value is taken, so the local owns it.
    case borrow
}
