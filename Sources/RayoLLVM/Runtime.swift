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

    /// Parses the runtime into `program`'s context. Declares in `program`'s module the functions the program calls,
    /// and defines there the constant the runtime reads.
    init(for program: borrowing ProgramEmitter) throws(LLVMError) {
        // Link the runtime's files together, in a module of their own for the program's target, so that it links
        // into the program's.
        let runtime = program.context.makeModule(named: "runtime")
        Self.matchTarget(of: runtime, to: program.module)
        for file in ProgramRuntime.files {
            let parsed = try program.context.parseModule(file.llvmIR, named: file.name)
            Self.matchTarget(of: parsed, to: program.module)
            try runtime.link(parsed)
        }

        // Declare the functions the program calls, and define the constant the runtime reads, in the program.
        functions = RuntimeFunctions(
            printInt: try Self.declare("rayo.print_int", from: runtime, in: program.module),
            printBool: try Self.declare("rayo.print_bool", from: runtime, in: program.module),
            panic: try Self.declare("rayo.panic", from: runtime, in: program.module),
        )
        let exitCode = program.context.integerType(I32.self).constant(Int64(ProgramRuntime.panicExitCode))
        program.module.addGlobal(named: "rayo.panic_exit_code", initializer: exitCode).setConstant()
        module = runtime
    }

    /// Links the runtime into `program`, the module it was parsed for.
    consuming func link(into program: borrowing Module) throws(LLVMError) {
        try program.link(module)
    }

    /// Sets `module` to build for `program`'s target and data layout.
    private static func matchTarget(of module: borrowing Module, to program: borrowing Module) {
        module.target = program.target
        module.dataLayout = program.dataLayout
    }

    /// Declares in `program` the function `name` that `runtime` defines.
    private static func declare(
        _ name: String, from runtime: borrowing Module, in program: borrowing Module,
    ) throws(LLVMError) -> Function {
        // A function the runtime doesn't define is a fault in the runtime rayoc carries.
        guard let definition = runtime.function(named: name) else {
            throw LLVMError(message: "the runtime defines no function '\(name)'")
        }
        return program.addFunction(named: definition.name, type: definition.type)
    }
}
