import RayoIR
import RayoLLVM

/// Compiles an executable program to object code for the host, as a build of the source at `sourcePath`.
struct Emit: CompilationStep {
    var mode: BuildMode
    var sourcePath: String

    func run(_ executable: IRExecutable) throws(CompilationError) -> [UInt8] {
        do {
            return try LLVMEmitter.objectCode(for: executable, sourcePath: sourcePath,
                                              checksOverflow: mode.checksOverflow, optimizes: mode.optimizes)
        } catch {
            // LLVM fails only through a fault in rayoc or in LLVM, never one in the program.
            throw .failed("internal error: \(error.message)")
        }
    }
}
