/// An operation in IR that breaks the IR's types, which no lowering of a checked program makes: a fault in the
/// compiler, never in the program.
public struct IRViolation: Error, Equatable, CustomStringConvertible {
    /// The name of the function whose body holds the operation, such as `f(_: Int)`.
    public var function: String
    /// What the operation does wrong, such as `the IR gives '+' an operand of type Bool, where it takes Int`.
    public var message: String

    public init(function: String, message: String) {
        self.function = function
        self.message = message
    }

    public var description: String {
        "in '\(function)': \(message)"
    }
}
