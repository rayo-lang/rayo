import RayoSema

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Equatable, Sendable {
    /// The program's structs, laid out.
    public var types: TypeTable
    public var functions: FunctionTable
    /// The body of each function that has one.
    public var bodies: [FunctionID: IRBody]
    /// The function a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?

    public init(types: TypeTable, functions: FunctionTable, bodies: [FunctionID: IRBody], main: FunctionID?) {
        self.types = types
        self.functions = functions
        self.bodies = bodies
        self.main = main
    }

    /// The ID and the body of each function that has a body, in the order of their IDs.
    public var definedFunctions: [(id: FunctionID, body: IRBody)] {
        functions.ids.compactMap { id in bodies[id].map { (id, $0) } }
    }
}
