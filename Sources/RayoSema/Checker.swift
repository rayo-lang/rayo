import RayoDiagnostics
import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns its checked program, which holds a body for each function whose body isn't
    /// tainted, with the errors checking found.
    public static func check(_ file: SourceFile) -> (program: CheckedProgram, diagnostics: [Diagnostic]) {
        let checker = FileChecker(file)
        let program = checker.check()
        return (program, checker.errors.list.inSourceOrder)
    }
}
