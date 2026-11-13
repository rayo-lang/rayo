import RayoDiagnostics
import RayoIR

/// Checks, in a debug build of `rayoc`, that the IR a stage gives keeps the IR's types, and gives it on as it is.
struct VerifyIR: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) throws(CompilationError) -> IRProgram? {
        // A release build of `rayoc` takes its stages' IR on trust, and spends no time checking it.
        #if DEBUG
        // IR that breaks its types is a fault in `rayoc`, never in the program.
        if let violation = IRVerifier.verify(program) { throw .failed("internal error: \(violation)") }
        #endif
        return program
    }
}
