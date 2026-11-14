/// A checked program: every declaration of the file, and the body of each function whose body isn't tainted, in
/// which every name is resolved, and every expression has its type.
///
/// A body is tainted when checking it reported an error, it holds a statement that failed to parse, or it reaches a
/// declaration that failed. A tainted function is a declaration with no body, which no later stage checks.
public struct CheckedProgram: Sendable {
    public var types: TypeTable
    public var functions: FunctionTable
    /// The body of each function that has one, and isn't tainted.
    public var bodies: [FunctionID: CheckedBody]
    /// The file's first `main`, which a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?
    /// Whether a function that failed to parse may have been the file's `main`: one that failed before its name, or
    /// named `main`.
    public var mainMayHaveFailed: Bool

    public init(
        types: TypeTable, functions: FunctionTable, bodies: [FunctionID: CheckedBody], main: FunctionID?,
        mainMayHaveFailed: Bool = false,
    ) {
        self.types = types
        self.functions = functions
        self.bodies = bodies
        self.main = main
        self.mainMayHaveFailed = mainMayHaveFailed
    }
}
