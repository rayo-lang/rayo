import RayoIR
import RayoOwnership

/// Checks that some code reads each value a lowered program assigns to a local.
struct CheckUnusedValues: CompilationStep {
    func run(_ program: IRProgram) throws(CompilationError) -> IRProgram {
        let diagnostics = UnusedValueChecker.check(program)
        // A program that assigns a value no code reads is rejected with each place it does.
        guard diagnostics.isEmpty else { throw .rejected(diagnostics) }
        return program
    }
}
