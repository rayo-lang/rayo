import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that a lowered program moves no value out of a borrowed parameter or an array's element, and gives it on
/// without the bodies of the functions that do.
struct CheckMoves: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        let found = MoveChecker.check(program)
        errors += found.values.joined()
        return program.withoutBodies(failing: found)
    }
}
