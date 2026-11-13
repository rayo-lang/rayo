/// What a call calls.
public enum Callee: Hashable, Sendable {
    case builtin(Builtin)
    case function(FunctionID)

    /// The name of what the call calls, and its parameters, such as `print(_: Int)`, where `functions` declares the
    /// program's functions.
    public func name(in functions: FunctionTable) -> String {
        switch self {
        case .builtin(let builtin): Signature(of: builtin).description
        case .function(let id): functions[id].name
        }
    }

    /// The types of the parameters of what the call calls, in order, where `functions` declares the program's
    /// functions.
    public func parameters(in functions: FunctionTable) -> [RayoType] {
        switch self {
        case .builtin(let builtin): builtin.parameterTypes
        case .function(let id): functions[id].parameters
        }
    }

    /// The type of the result of what the call calls, where `functions` declares the program's functions.
    public func result(in functions: FunctionTable) -> RayoType {
        switch self {
        case .builtin(let builtin): builtin.result
        case .function(let id): functions[id].result
        }
    }
}
