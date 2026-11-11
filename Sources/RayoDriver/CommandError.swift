/// Why a `rayo` command stopped before it could finish.
enum CommandError: Error, Equatable {
    /// `rayoc` didn't compile the file, and exited with `exitCode` after writing `errors`.
    case compileFailed(exitCode: Int32, errors: String)
    /// `rayo` couldn't go on, for a reason its message gives, after `rayoc` wrote `errors`.
    case failed(String, errors: String = "")

    /// The same error, with `written`, which `rayoc` wrote before it, written first.
    func after(_ written: String) -> CommandError {
        switch self {
        case .compileFailed(let exitCode, let errors): .compileFailed(exitCode: exitCode, errors: written + errors)
        case .failed(let message, let errors): .failed(message, errors: written + errors)
        }
    }
}
