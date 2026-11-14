import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that a lowered program uses each local only where it holds a value, and assigns each `let` at most once.
struct CheckOwnership: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        errors += InitializationChecker.check(program)
        return program
    }
}
