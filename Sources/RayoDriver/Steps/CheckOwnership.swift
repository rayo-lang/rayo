import RayoIR
import RayoOwnership

/// Checks that a lowered program uses each local only where it holds a value, and assigns each `let` at most once.
struct CheckOwnership: CompilationStep {
    func run(_ program: IRProgram) throws(CompilationError) -> IRProgram {
        let diagnostics = InitializationChecker.check(program)
        // A program that breaks either rule is rejected with each place it does.
        guard diagnostics.isEmpty else { throw .rejected(diagnostics) }
        return program
    }
}
