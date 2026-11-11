import RayoIR
import RayoLLVM

/// Compiles a program to object code for the host, as a build of the source at `sourcePath`.
struct Emit: CompilationStep {
    var mode: BuildMode
    var sourcePath: String

    func run(_ program: IRProgram) throws(CompilationError) -> [UInt8] {
        do {
            return try LLVMEmitter.objectCode(for: program, sourcePath: sourcePath, checksOverflow: mode == .debug,
                                              optimizes: mode == .release)
        } catch {
            // LLVM fails only through a fault in rayoc or in LLVM, never one in the program.
            throw .failed("internal error: \(error.message)")
        }
    }
}
