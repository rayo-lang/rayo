import RayoDiagnostics

/// What a run of `rayoc` ends with: its exit code, and what it wrote to its standard output and error.
public struct RunResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var errors: String
    /// The errors found in the program, which `errors` also shows.
    public var diagnostics: [Diagnostic]

    public init(exitCode: Int32, output: String, errors: String, diagnostics: [Diagnostic] = []) {
        self.exitCode = exitCode
        self.output = output
        self.errors = errors
        self.diagnostics = diagnostics
    }
}
