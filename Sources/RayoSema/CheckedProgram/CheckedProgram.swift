/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    /// The file's functions, indexed by `FunctionID`.
    public var functions: [CheckedFunction]
    public var main: FunctionID
}

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
