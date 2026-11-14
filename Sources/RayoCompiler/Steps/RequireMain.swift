import RayoDiagnostics
import RayoIR
import RayoSource

/// Passes on a program that has a `main`, which an executable starts at, and reports a library, which has none.
struct RequireMain: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRExecutable? {
        // A library is reported at the start of its file, since no line of it is wrong, and makes no executable.
        guard let executable = IRExecutable(program) else {
            let start = SourceLocation(line: 1, column: 1, offset: 0)
            errors.append(Diagnostic(.noMain, at: SourceRange(start, start)))
            return nil
        }
        return executable
    }
}
