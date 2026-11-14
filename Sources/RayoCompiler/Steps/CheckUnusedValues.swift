import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that some code reads each value a lowered program assigns to a local, and gives it on without the bodies of
/// the functions that leave one unread.
struct CheckUnusedValues: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        let found = UnusedValueChecker.check(program)
        errors += found.values.joined()
        return program.withoutBodies(failing: found)
    }
}
