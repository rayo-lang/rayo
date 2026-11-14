import RayoDiagnostics
import RayoSema
import RayoSyntax

/// Checks a file's syntax tree, and gives the program it makes, adding its errors to the compile's errors. The program
/// holds no body for a function whose body is tainted, so the steps after this one skip it.
struct Check: CompilationStep {
    func run(_ file: SourceFile, errors: inout [Diagnostic]) -> CheckedProgram? {
        let checked = Checker.check(file)
        errors += checked.diagnostics
        return checked.program
    }
}
