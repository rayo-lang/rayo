import RayoIR
import RayoSema

/// Lowers a checked program to Rayo IR.
struct Lower: CompilationStep {
    func run(_ program: CheckedProgram) -> IRProgram {
        Lowering.lower(program)
    }
}
