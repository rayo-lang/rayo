import RayoSema

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Equatable, Sendable {
    /// The program's functions, indexed by `FunctionID`.
    public var functions: [IRFunction]
    public var main: FunctionID

    public init(functions: [IRFunction], main: FunctionID) {
        self.functions = functions
        self.main = main
    }
}
