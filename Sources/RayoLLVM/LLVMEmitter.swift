internal import CLLVM
import RayoIR

/// Compiles Rayo IR to object code for the host, through LLVM.
public enum LLVMEmitter {
    /// The object code of `program` and the program runtime, whose panics name `sourcePath` as the file they
    /// happen in, ready to link into an executable for the host. Integer overflow panics where `checksOverflow` is
    /// true, and wraps where it's false; `optimizes` runs LLVM's optimisations over the module.
    public static func objectCode(for program: IRProgram, sourcePath: String, checksOverflow: Bool,
                                  optimizes: Bool) throws(LLVMError) -> [UInt8] {
        let target = try TargetMachine(optimizes: optimizes)
        let module = ModuleBuilder(named: sourcePath, for: target)
        let runtime = try Runtime(in: module)

        ProgramEmitter(module: module, runtime: runtime, sourcePath: sourcePath, checksOverflow: checksOverflow)
            .emit(program)
        try runtime.link(into: module)
        try module.verify()

        return try target.objectCode(of: module)
    }
}

/// A fault in `rayoc`, or in the LLVM it compiles with, that stops LLVM compiling a program: never one in the
/// program itself.
public struct LLVMError: Error {
    public var message: String
}

/// Emits a program into an LLVM module, calling the runtime's functions.
struct ProgramEmitter {
    let module: ModuleBuilder
    let runtime: Runtime
    let sourcePath: String
    let checksOverflow: Bool

    /// Defines the program's `main` as `rayo.main`, which the runtime's C entry point runs.
    func emit(_ program: IRProgram) {
        let main = module.addFunction("rayo.main", returning: module.void)
        var function = FunctionEmitter(function: program.main, into: main.value, program: self)
        function.emit()
    }
}
