import LLVM
import RayoRuntime

/// The program runtime, parsed into a program's context until it is linked into the program's module, and the
/// functions of it that the program calls, declared in that module.
struct Runtime {
    /// The C entry point the runtime defines, which is the one symbol a program's object code exports.
    static let entryPoint = "main"

    let printInt: FunctionValue
    let panic: FunctionValue

    init(in module: ModuleBuilder) throws(LLVMError) {
        for file in ProgramRuntime.files {
            try module.parse(file.llvmIR, named: file.name)
        }
        printInt = try module.declare("rayo.print_int")
        panic = try module.declare("rayo.panic")
        module.addConstant("rayo.panic_exit_code", int32: ProgramRuntime.panicExitCode)
    }

    /// Links the runtime into `module`, the module it was parsed for.
    func link(into module: ModuleBuilder) throws(LLVMError) {
        try module.linkParsed()
    }
}
