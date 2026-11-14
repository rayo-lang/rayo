import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that a lowered program uses each local only where it holds a value, and assigns each `let` at most once,
/// and gives it on without the bodies of the functions that don't.
struct CheckOwnership: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        let found = InitializationChecker.check(program)
        errors += found.values.joined()
        return program.withoutBodies(failing: found)
    }
}
