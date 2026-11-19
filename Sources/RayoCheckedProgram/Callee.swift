/// What a call calls.
public enum Callee: Hashable, Sendable {
    case builtin(Builtin)
    case function(FunctionID)

    /// The name of what the call calls, and its parameters, such as `print(_: Int)`, where `functions` declares the
    /// program's functions.
    public func name(in functions: FunctionTable) -> String {
        switch self {
        case .builtin(let builtin): Self.name(of: builtin)
        case .function(let id): functions[id].name
        }
    }

    /// The name of `builtin` and its parameters, as a function the program declares with them is named.
    private static func name(of builtin: Builtin) -> String {
        let parameters = builtin.parameters.map(\.description).joined(separator: ", ")
        return "\(builtin.name.spelling)(\(parameters))"
    }

    /// The parameters of what the call calls, in order, where `functions` declares the program's functions.
    public func parameters(in functions: FunctionTable) -> [FunctionParameter] {
        switch self {
        case .builtin(let builtin): builtin.parameters
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
