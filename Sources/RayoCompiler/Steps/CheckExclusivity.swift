import RayoDiagnostics
import RayoIR
import RayoOwnership

/// Works out where each access of a lowered program ends, and checks that no two accesses conflict. It gives on the
/// program with the end of each access written in, which the emitter receives, without the bodies of the functions
/// whose accesses conflict.
struct CheckExclusivity: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        let (ended, found) = ExclusivityChecker.check(program)
        errors += found.values.joined()
        return ended.withoutBodies(failing: found)
    }
}
