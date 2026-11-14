import RayoDiagnostics
import RayoSema
import RayoSyntax

/// Checks a file's syntax tree, and gives the program it makes, adding its errors to the compile's errors.
struct Check: CompilationStep {
    func run(_ file: SourceFile, errors: inout [Diagnostic]) -> CheckedProgram? {
        let checked = Checker.check(file)
        errors += checked.diagnostics
        // A file that doesn't check makes no program.
        return checked.program
    }
}
