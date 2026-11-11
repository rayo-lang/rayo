import LLVM
import RayoRuntime

/// The program runtime, parsed into a program's context until it is linked into the program's module.
struct Runtime: ~Copyable {
    /// The C entry point the runtime defines, which is the one symbol a program's object code exports.
    static let entryPoint = "main"

    /// The functions of the runtime that the program calls, declared in the program's module.
    let functions: RuntimeFunctions
    /// The runtime's files, linked together.
    private let module: Module

    init(in program: ModuleBuilder) throws(LLVMError) {
        // Link the runtime's files together, in a module of their own.
        let runtime = program.makeModule(named: "runtime")
        for file in ProgramRuntime.files {
            try runtime.link(program.parse(file.llvmIR, named: file.name))
        }

        // Declare the functions the program calls, and define the constant the runtime reads, in the program.
        functions = RuntimeFunctions(
            printInt: try Self.declare("rayo.print_int", from: runtime, in: program),
            panic: try Self.declare("rayo.panic", from: runtime, in: program),
        )
        program.addConstant("rayo.panic_exit_code", int32: ProgramRuntime.panicExitCode)
        module = runtime
    }

    /// Links the runtime into `program`, the module it was parsed for.
    consuming func link(into program: ModuleBuilder) throws(LLVMError) {
        try program.link(module)
    }

    /// Declares in `program` the function `name` that `runtime` defines.
    private static func declare(
        _ name: String, from runtime: borrowing Module, in program: ModuleBuilder,
    ) throws(LLVMError) -> FunctionValue {
        // A function the runtime doesn't define is a fault in the runtime rayoc carries.
        guard let definition = runtime.function(named: name) else {
            throw LLVMError(message: "the runtime defines no function '\(name)'")
        }
        return program.declare(definition)
    }
}
