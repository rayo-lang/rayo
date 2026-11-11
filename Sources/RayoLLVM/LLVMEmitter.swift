import LLVM
import RayoIR

/// Compiles Rayo IR to object code for the host, through LLVM.
public enum LLVMEmitter {
    /// The object code of `executable` and the program runtime, whose panics name `sourcePath` as the file they
    /// happen in, ready to link into an executable for the host. Integer overflow panics where `checksOverflow` is
    /// true, and wraps where it's false; `optimizes` runs LLVM's optimisations over the module.
    public static func objectCode(for executable: IRExecutable, sourcePath: String, checksOverflow: Bool,
                                  optimizes: Bool) throws(LLVMError) -> [UInt8] {
        let target = try TargetMachine(optimizes: optimizes)
        let program = ProgramEmitter(sourcePath: sourcePath, for: target, checksOverflow: checksOverflow)
        let runtime = try Runtime(for: program)

        program.emit(executable, calling: runtime.functions)
        try runtime.link(into: program.module)
        try ready(program.module, for: target, exporting: [Runtime.entryPoint])
        return try objectCode(of: program.module, for: target)
    }

    /// Readies `module` to compile as `target`'s build: hides every definition but the functions `exported` names
    /// from code outside the module, checks the module is well formed, and optimises it if `target` optimises.
    /// Throws the errors LLVM has reported in the module's context, if any.
    static func ready(
        _ module: borrowing Module, for target: borrowing TargetMachine, exporting exported: Set<String>,
    ) throws(LLVMError) {
        hideDefinitions(in: module, except: exported)
        try module.verify()
        if target.optimizes { try target.optimize(module) }
        try checkReportedErrors(in: module)
    }

    /// Writes the object code of `module`, once it is ready, as `target` compiles it, and returns it.
    static func objectCode(of module: borrowing Module, for target: borrowing TargetMachine) throws(LLVMError)
        -> [UInt8] {
        let objectCode = try target.objectCode(of: module)
        // LLVM can report an error as it writes object code and write it all the same, wrongly.
        try checkReportedErrors(in: module)
        return objectCode
    }

    /// Throws the errors LLVM has reported in `module`'s context, if any.
    private static func checkReportedErrors(in module: borrowing Module) throws(LLVMError) {
        // Only an error fails the module; a warning fails nothing.
        if module.reportedErrorCount > 0 { throw module.error("LLVM reported errors:", reportedAfter: 0) }
    }

    /// Gives every function and global `module` defines, but the functions `exported` names and LLVM's own globals,
    /// a linkage that keeps it out of the executable's symbols.
    private static func hideDefinitions(in module: borrowing Module, except exported: Set<String>) {
        // Functions become internal, so that optimisation can drop those nothing calls.
        for function in module.functions where isHideable(function) && !exported.contains(function.name) {
            function.setLinkage(.internal)
        }

        // Globals become private, so that optimisation can drop those nothing reads.
        for global in module.globals where isHideable(global) {
            global.setLinkage(.private)
        }
    }

    /// Whether `value` is a definition, and not one of LLVM's own, such as `llvm.used` or `llvm.global_ctors`,
    /// whose linkage LLVM requires to stay as it is.
    private static func isHideable(_ value: some GlobalValue) -> Bool {
        !value.isDeclaration && !value.name.hasPrefix("llvm.")
    }
}
