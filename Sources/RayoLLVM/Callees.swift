import RayoSema

/// The functions that a program's calls go to: its own, and the runtime's that the prelude names.
struct Callees {
    /// The program's functions, indexed by `FunctionID`.
    let functions: [DeclaredFunction]
    let printInt: DeclaredFunction
    let printBool: DeclaredFunction

    /// The function that `callee` names: each of the prelude's `print`s is the runtime's.
    subscript(callee: Callee) -> DeclaredFunction {
        switch callee {
        case .printInt: printInt
        case .printBool: printBool
        case .function(let id): functions[id.index]
        }
    }
}
