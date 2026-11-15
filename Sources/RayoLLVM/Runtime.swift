import LLVM
import RayoRuntime

/// The program runtime, parsed into a program's context until it is linked into the program's module.
struct Runtime: ~Copyable {
    /// The C entry point the runtime defines, which is the one symbol a program's object code exports.
    static let entryPoint = "main"

    /// The runtime's files, linked together.
    private let module: Module

    /// Parses the runtime into `context`, its functions carrying `functionAttributes`, and defines in `program`, a
    /// module of that context, the constant the runtime reads.
    init(
        in context: borrowing Context, for program: borrowing Module, functionAttributes: [FunctionAttribute],
    ) throws(LLVMError) {
        // Link the runtime's files together, in a module of their own for the program's target, so that it links
        // into the program's.
        let runtime = context.makeModule(named: "runtime")
        Self.matchTarget(of: runtime, to: program)
        for file in ProgramRuntime.files {
            let parsed = try context.parseModule(file.llvmIR, named: file.name)
            Self.matchTarget(of: parsed, to: program)
            try runtime.link(parsed)
        }

        // Give each function the runtime defines the attributes the target needs of every function.
        for function in runtime.functions where !function.isDeclaration { function.add(functionAttributes) }

        // Define the constant the runtime reads in the program.
        let exitCode = context.integerType(I32.self).constant(Int64(ProgramRuntime.panicExitCode))
        program.addGlobal(named: RuntimeConstant.panicExitCode.symbol, initializer: exitCode).setConstant()
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
}
