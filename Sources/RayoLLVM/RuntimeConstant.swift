/// A constant that the program defines and the runtime it links reads.
enum RuntimeConstant {
    /// The exit code of a program that panics, an `i32`.
    case panicExitCode

    /// The symbol the program and the runtime name the constant by.
    var symbol: String {
        switch self {
        case .panicExitCode: "rayo.panic_exit_code"
        }
    }
}
