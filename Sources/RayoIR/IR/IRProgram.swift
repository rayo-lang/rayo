import RayoSema

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Equatable, Sendable {
    /// The program's structs, laid out.
    public var types: TypeTable
    /// The program's functions, indexed by `FunctionID`.
    public var functions: [IRFunction]
    /// The function a run of the program starts at, or nil for a library, which has none.
    public var main: FunctionID?

    public init(types: TypeTable, functions: [IRFunction], main: FunctionID?) {
        self.types = types
        self.functions = functions
        self.main = main
    }
}
