import RayoDiagnostics

/// Why a compile stopped before it could finish.
enum CompilationError: Error, Equatable {
    /// The program has errors, each one a step found, in source order.
    case rejected([Diagnostic])
    /// `rayoc` couldn't go on, for a reason its message gives.
    case failed(String)
}
