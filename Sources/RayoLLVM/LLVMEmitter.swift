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
        module.hideDefinitions(except: Runtime.entryPoint)
        try module.verify()
        let objectCode = try target.objectCode(of: module)

        try module.checkReportedErrors()
        return objectCode
    }
}
