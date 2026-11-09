internal import CLLVM
import RayoRuntime

/// The program runtime, parsed into a program's context until it is linked into the program's module, and the
/// functions of it that the program calls, declared in that module.
struct Runtime {
    /// The C entry point the runtime defines, which is the one symbol a program's object code exports.
    static let entryPoint = "main"

    private let modules: [LLVMModuleRef]
    let printInt: FunctionValue
    let panic: FunctionValue

    init(in module: ModuleBuilder) throws(LLVMError) {
        var modules: [LLVMModuleRef] = []
        for file in ProgramRuntime.files {
            modules.append(try module.parse(file.llvmIR, named: file.name))
        }
        self.modules = modules
        printInt = try module.declare("rayo.print_int", definedIn: modules)
        panic = try module.declare("rayo.panic", definedIn: modules)
        module.addConstant("rayo.panic_exit_code", int32: ProgramRuntime.panicExitCode)
    }

    /// Links the runtime into `module`, which consumes the runtime's own modules.
    func link(into module: ModuleBuilder) throws(LLVMError) {
        for runtimeModule in modules {
            try module.link(runtimeModule)
        }
    }
}
