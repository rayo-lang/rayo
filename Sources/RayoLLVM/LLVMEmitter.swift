import LLVM
import RayoIR

/// Compiles Rayo IR to object code for the host, through LLVM.
package enum LLVMEmitter {
    /// The object code of `executable` and the program runtime, whose panics name `sourcePath` as the file they
    /// happen in, compiled for `build` and ready to link into an executable for the host.
    package static func objectCode(for executable: IRExecutable, sourcePath: String, build: Build) throws(LLVMError)
        -> [UInt8] {
        let target = try TargetMachine(optimizes: build.optimizes)
        let program = ProgramEmitter(sourcePath: sourcePath, for: target, build: build)
        let runtime = try Runtime(for: program)

        try program.emit(executable, calling: runtime.functions)
        try runtime.link(into: program.module)
        try ready(program.module, for: target, exporting: [Runtime.entryPoint])
        return try writeObjectCode(of: program.module, for: target)
    }

    /// Readies `module` to compile as `target`'s build: hides every definition but the functions `exported` names
    /// from code outside the module, checks the module is well formed, and optimises it if `target` optimises.
    /// Throws the errors LLVM has reported in the module's context, if any.
    static func ready(
        _ module: borrowing Module, for target: borrowing TargetMachine, exporting exported: Set<String>,
    ) throws(LLVMError) {
        module.hideDefinitions(except: exported)
        try module.verify()
        if target.optimizes { try target.optimize(module) }
        try module.checkReportedErrors()
    }

    /// Writes the object code of `module`, once it is ready, as `target` compiles it, and returns it.
    static func writeObjectCode(of module: borrowing Module, for target: borrowing TargetMachine) throws(LLVMError)
        -> [UInt8] {
        let objectCode = try target.objectCode(of: module)
        // LLVM can report an error as it writes object code and write it all the same, wrongly.
        try module.checkReportedErrors()
        return objectCode
    }
}
