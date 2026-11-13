import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that some code reads each value a lowered program assigns to a local.
struct CheckUnusedValues: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        errors += UnusedValueChecker.check(program)
        return program
    }
}
