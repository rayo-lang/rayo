/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    public var types: TypeTable
    /// The file's functions, indexed by `FunctionID`.
    public var functions: [CheckedFunction]
    public var main: FunctionID
}
