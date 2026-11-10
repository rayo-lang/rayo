/// What a call calls.
public enum Callee: Hashable, Sendable {
    /// The prelude's `print(_: Int)`, which writes the integer and a newline to standard output.
    case printInt
    case function(FunctionID)
}
