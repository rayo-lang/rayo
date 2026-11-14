import RayoDiagnostics
import RayoIR
import RayoSource

/// Passes on a program that has a `main`, which an executable starts at, and reports a library, which has none.
struct RequireMain: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRExecutable? {
        guard let executable = IRExecutable(program) else {
            // A function that failed to parse may have been the `main`, so its absence isn't reported. A library is
            // reported at the start of its file, since no line of it is wrong. Neither makes an executable.
            if !program.mainMayHaveFailed {
                let start = SourceLocation(line: 1, column: 1, offset: 0)
                errors.append(Diagnostic(.noMain, at: SourceRange(start, start)))
            }
            return nil
        }
        return executable
    }
}
