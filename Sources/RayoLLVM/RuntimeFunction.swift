import RayoSema

/// A function that one side of a program and its runtime defines and the other calls: one the runtime defines for the
/// program's code to call, or the program's `main`, which the runtime's entry point calls.
enum RuntimeFunction: CaseIterable {
    /// The program's `main`, which takes nothing and returns nothing.
    case main
    /// The function that writes a value of a scalar type and a newline to standard output, and takes the value as
    /// Rayo's convention passes it.
    case print(ScalarType)
    /// The function that writes a panic's message to standard error and ends the program with the panic exit code. It
    /// takes a pointer to the message's bytes and their count as an Int.
    case panic

    /// Every runtime function: the program's `main`, the print of each of the prelude's scalar types, and the panic.
    static var allCases: [RuntimeFunction] {
        [.main] + ScalarType.prelude.map(RuntimeFunction.print) + [.panic]
    }

    /// The symbol the program and the runtime name the function by. No name that a program declares is one of these,
    /// since none is written with a dot.
    var symbol: String {
        switch self {
        case .main: "rayo.main"
        case .print(let scalar): "rayo.print_\(scalar.name.lowercased())"
        case .panic: "rayo.panic"
        }
    }
}
