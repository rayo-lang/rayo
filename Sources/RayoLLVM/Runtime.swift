internal import CLLVM
import RayoRuntime

/// The program runtime as one program uses it: the runtime's modules, held apart until they are linked into the
/// program's module, and the runtime functions that the program calls, declared in the program's module.
struct Runtime {
    /// The C entry point the runtime defines, which is the one symbol a program's object code exports.
    static let entryPoint = "main"

    private let modules: [LLVMModuleRef]
    /// Prints an Int on a line of its own.
    let printInt: FunctionValue
    /// Reports a panic with a message, and ends the program.
    let panic: FunctionValue

    /// Parses the runtime in `module`'s context, declares in `module` the functions a program calls, and defines
    /// there the exit code the runtime panics with.
    init(in module: ModuleBuilder) throws(LLVMError) {
        // Parse each of the runtime's files into a module of its own.
        var modules: [LLVMModuleRef] = []
        for file in ProgramRuntime.files {
            modules.append(try module.parse(file.llvmIR, named: file.name))
        }
        self.modules = modules

        // Declare the functions the program calls, and give the runtime the exit code that `rayoc` reports.
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
