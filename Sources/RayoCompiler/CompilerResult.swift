import RayoDiagnostics

/// What a run of `rayoc` gives: its exit code, and what it writes to its standard error and its standard output.
public struct CompilerResult: Equatable, Sendable {
    public var exitCode: Int32
    /// The program's errors and warnings, why `rayoc` couldn't go on, or how to use it.
    public var errors: String
    /// The errors and warnings found in the program, which `errors` also shows.
    public var diagnostics: [Diagnostic]
    /// What a stage made of the program, where the arguments ask for it to be printed.
    public var standardOutput: String

    public init(exitCode: Int32, errors: String, diagnostics: [Diagnostic] = [], standardOutput: String = "") {
        self.exitCode = exitCode
        self.errors = errors
        self.diagnostics = diagnostics
        self.standardOutput = standardOutput
    }
}
