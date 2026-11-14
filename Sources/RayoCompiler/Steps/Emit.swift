import RayoDiagnostics
import RayoIR
import RayoLLVM

/// Compiles an executable program to object code for the host, as a build of the source at `sourcePath`.
struct Emit: CompilationStep {
    var build: Build
    var sourcePath: String

    func run(_ executable: IRExecutable, errors: inout [Diagnostic]) throws(CompilationError) -> [UInt8]? {
        do {
            return try LLVMEmitter.objectCode(for: executable, sourcePath: sourcePath, build: build)
        } catch {
            // LLVM fails only through a fault in rayoc or in LLVM, never one in the program.
            throw .failed("internal error: \(error.message)")
        }
    }
}
