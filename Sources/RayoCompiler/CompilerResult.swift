import RayoDiagnostics

/// What a run of `rayoc` gives: its exit code, and what it writes to its standard error.
public struct CompilerResult: Equatable, Sendable {
    public var exitCode: Int32
    /// The program's errors, why `rayoc` couldn't go on, or how to use it.
    public var errors: String
    /// The errors found in the program, which `errors` also shows.
    public var diagnostics: [Diagnostic]

    public init(exitCode: Int32, errors: String, diagnostics: [Diagnostic] = []) {
        self.exitCode = exitCode
        self.errors = errors
        self.diagnostics = diagnostics
    }
}
