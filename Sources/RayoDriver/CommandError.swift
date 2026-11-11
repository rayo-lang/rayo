/// Why a `rayo` command stopped before it could finish.
enum CommandError: Error, Equatable {
    /// `rayoc` didn't compile the file, and exited with `exitCode` after writing `errors`.
    case compileFailed(exitCode: Int32, errors: String)
    /// `rayo` couldn't go on, for a reason its message gives, after `rayoc` wrote `written`.
    case failed(String, written: String = "")

    /// The same error, with `errors`, which `rayoc` wrote before it, written first.
    func after(_ errors: String) -> CommandError {
        switch self {
        case .compileFailed(let exitCode, let written): .compileFailed(exitCode: exitCode, errors: errors + written)
        case .failed(let message, let written): .failed(message, written: errors + written)
        }
    }
}
