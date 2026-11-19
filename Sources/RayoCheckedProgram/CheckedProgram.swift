/// A checked program: every declaration of the file, and the body of each function whose body isn't tainted, in
/// which every name is resolved, and every expression has its type.
///
/// A body is tainted when checking it reported an error that left it without a meaning, it holds a statement that
/// failed to parse, or it reaches a declaration that failed. A tainted function is a declaration with no body, which
/// no later stage checks. A body that reported only errors that left its meaning whole, such as a value no code uses,
/// is kept, so the later stages report their errors in it; a program with such an error is never emitted.
public struct CheckedProgram: Sendable {
    public var types: TypeTable
    public var functions: FunctionTable
    /// The body of each function that has one, and isn't tainted.
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
