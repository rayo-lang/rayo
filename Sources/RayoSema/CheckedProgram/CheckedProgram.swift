/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    public var types: TypeTable
    /// The file's functions, indexed by `FunctionID`.
    public var functions: [CheckedFunction]
    /// The file's first `main`, which a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?
}
