/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    public var types: TypeTable
    public var functions: FunctionTable
    /// The body of each function that has one.
    public var bodies: [FunctionID: CheckedBody]
    /// The file's first `main`, which a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?

    public init(types: TypeTable, functions: FunctionTable, bodies: [FunctionID: CheckedBody], main: FunctionID?) {
        self.types = types
        self.functions = functions
        self.bodies = bodies
        self.main = main
    }
}
