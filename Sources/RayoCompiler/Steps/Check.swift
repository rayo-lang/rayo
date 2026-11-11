import RayoSema
import RayoSyntax

/// Checks a file's syntax tree, and gives the program it makes.
struct Check: CompilationStep {
    func run(_ file: SourceFile) throws(CompilationError) -> CheckedProgram {
        let checked = Checker.check(file)
        // A file that doesn't check is rejected with its errors.
        guard let program = checked.program else { throw .rejected(checked.diagnostics) }
        return program
    }
}
