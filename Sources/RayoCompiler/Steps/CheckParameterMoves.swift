import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Checks that a lowered program moves no value out of a borrowed parameter.
struct CheckParameterMoves: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        errors += ParameterMoveChecker.check(program)
        return program
    }
}
