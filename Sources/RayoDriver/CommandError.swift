/// Why a `rayo` command stopped before it could finish.
enum CommandError: Error, Equatable {
    /// `rayoc` didn't compile the file, and exited with `exitCode` after writing `errors`.
    case compileFailed(exitCode: Int32, errors: String)
    /// `rayo` couldn't go on, for a reason its message gives.
    case failed(String)
}
