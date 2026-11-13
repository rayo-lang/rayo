import RayoIR
import RayoOwnership

/// Checks that a lowered program moves no value out of a borrowed parameter.
struct CheckParameterMoves: CompilationStep {
    func run(_ program: IRProgram) throws(CompilationError) -> IRProgram {
        let diagnostics = ParameterMoveChecker.check(program)
        // A program that moves out of a borrowed parameter is rejected with each place it does.
        guard diagnostics.isEmpty else { throw .rejected(diagnostics) }
        return program
    }
}
