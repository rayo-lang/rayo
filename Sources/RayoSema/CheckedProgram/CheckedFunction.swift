/// A function of the checked program, with its locals and its checked body.
public struct CheckedFunction: Sendable {
    /// The function's name and parameters, such as `f()`, which no other function of the program has.
    public var name: String
    /// How many parameters the function takes, which are its first locals, in order.
    public var parameterCount: Int
    public var result: RayoType
    /// The function's locals, indexed by `LocalID`.
    public var locals: [CheckedLocal]
    public var body: [CheckedStmt]
}
