import RayoDiagnostics
import RayoIR
import RayoSource

/// Passes on a program that has a `main`, which an executable starts at, and rejects a library, which has none.
struct RequireMain: CompilationStep {
    func run(_ program: IRProgram) throws(CompilationError) -> IRProgram {
        // A library is reported at the start of its file, since no line of it is wrong.
        guard program.main != nil else {
            let start = SourceLocation(line: 1, column: 1, offset: 0)
            throw .rejected([Diagnostic(.noMain, at: SourceRange(start, start))])
        }
        return program
    }
}
