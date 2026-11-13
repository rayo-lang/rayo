import RayoDiagnostics
import RayoIR
import RayoSema

/// Lowers a checked program to Rayo IR, which finds no errors in it.
struct Lower: CompilationStep {
    func run(_ program: CheckedProgram, errors: inout [Diagnostic]) -> IRProgram? {
        Lowering.lower(program)
    }
}
