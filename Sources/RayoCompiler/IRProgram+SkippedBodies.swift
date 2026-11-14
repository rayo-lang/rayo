import RayoDiagnostics
import RayoIR
import RayoSema

extension IRProgram {
    /// The program without the body of each function that `found`, a step's diagnostics by function, holds an error
    /// for, so the steps after it skip those functions alone.
    func withoutBodies(failing found: [FunctionID: [Diagnostic]]) -> IRProgram {
        var program = self
        // A warning flags code that still has a meaning, so only an error fails its function.
        for (id, diagnostics) in found where diagnostics.contains(where: { $0.severity == .error }) {
            program.bodies[id] = nil
        }
        return program
    }
}
