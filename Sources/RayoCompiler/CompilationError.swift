import RayoDiagnostics

/// Why a compile stopped before it could finish.
enum CompilationError: Error, Equatable {
    /// The program has errors.
    case rejected([Diagnostic])
    /// `rayoc` couldn't go on, for a reason its message gives.
    case failed(String)
}
