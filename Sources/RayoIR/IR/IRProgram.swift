import RayoSema

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Sendable {
    /// The program's structs, and how a value of each type lies in memory.
    public var types: TypeTable
    /// The program's functions, indexed by `FunctionID`.
    public var functions: [IRFunction]
    public var main: FunctionID

    public init(types: TypeTable, functions: [IRFunction], main: FunctionID) {
        self.types = types
        self.functions = functions
        self.main = main
    }
}
