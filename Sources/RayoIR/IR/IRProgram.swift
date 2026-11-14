import RayoSema

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Equatable, Sendable {
    /// The program's structs, laid out.
    public var types: TypeTable
    public var functions: FunctionTable
    /// The body of each function that has one, and that no stage has found an error in.
    public var bodies: [FunctionID: IRBody]
    /// The function a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?
    /// Whether a function that failed to parse may have been the program's `main`: one that failed before its name,
    /// or named `main`.
    public var mainMayHaveFailed: Bool

    public init(
        types: TypeTable, functions: FunctionTable, bodies: [FunctionID: IRBody], main: FunctionID?,
        mainMayHaveFailed: Bool = false,
    ) {
        self.types = types
        self.functions = functions
        self.bodies = bodies
        self.main = main
        self.mainMayHaveFailed = mainMayHaveFailed
    }

    /// The ID and the body of each function that has a body, in the order of their IDs.
    public var definedFunctions: [(id: FunctionID, body: IRBody)] {
        functions.ids.compactMap { id in bodies[id].map { (id, $0) } }
    }
}
