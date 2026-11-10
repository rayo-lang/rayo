import RayoDiagnostics
import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns the checked program when it has no errors.
    public static func check(_ file: SourceFile) -> (program: CheckedProgram?, diagnostics: [Diagnostic]) {
        let checker = FileChecker(file)
        let program = checker.check()
        return (checker.errors.list.isEmpty ? program : nil, checker.errors.list.inSourceOrder)
    }
}
