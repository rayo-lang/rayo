import RayoDiagnostics

/// Why a compile stopped.
enum CompilationError: Error, Equatable {
    /// The program has errors.
    case rejected([Diagnostic])
    /// `rayoc` couldn't go on, for a reason its message gives.
    case failed(String)

    /// `error` as the reason a compile stopped, for an error that the host's tools or files threw.
    init(_ error: any Error) {
        self = switch error {
        // An error rayoc threw itself is already one.
        case let error as CompilationError: error
        // Any other is a failure that the error describes.
        default: .failed(error.localizedDescription)
        }
    }
}
