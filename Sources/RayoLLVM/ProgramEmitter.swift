import LLVM
import RayoIR
import RayoSema

/// Emits a program into an LLVM module of its own, which it owns with the context the module is made in and the
/// builder that adds to it.
struct ProgramEmitter: ~Copyable {
    let context = Context()
    let module: Module
    let builder: Builder
    /// The path of the program's source, which a panic names as the file it happens in.
    let sourcePath: String
    /// The build the program's code is emitted for.
    let build: Build

    /// Makes an empty module named `sourcePath`, configured to compile as `target` does.
    init(sourcePath: String, for target: borrowing TargetMachine, build: Build) {
        module = context.makeModule(named: sourcePath)
        builder = context.makeBuilder()
        target.configure(module)
        self.sourcePath = sourcePath
        self.build = build
    }

    /// Ends the emitter, handing on the module it emitted into.
    consuming func takeModule() -> Module {
        module
    }

    /// Defines the program's functions in the module, its structs as named LLVM types, calling `runtime`'s
    /// functions where the program calls the runtime. Throws where the IR gives an instruction a value of a type it
    /// doesn't take.
    func emit(_ executable: IRExecutable, calling runtime: RuntimeFunctions) throws(LLVMError) {
        let program = executable.program
        let lowering = SignatureLowering(types: LLVMTypes(program.types, in: context))
        let functions = program.functions.ids.map { declare($0, of: executable, using: lowering) }
        let callees = Callees(
            functions: functions,
            printInt: runtimeFunction(runtime.printInt, taking: .int, using: lowering),
            printBool: runtimeFunction(runtime.printBool, taking: .bool, using: lowering),
        )

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (id, body) in program.definedFunctions {
            var emitter = FunctionEmitter(body: body, of: program.functions[id], into: functions[id.index],
                                          callees: callees, lowering: lowering, panic: runtime.panic, in: self)
            try emitter.emit(in: self)
        }
    }

    /// Declares the function `id`: the program's `main` as `rayo.main`, which the runtime's C entry point runs, and
    /// any other function by its name and parameters, such as `f(_: Int)`.
    private func declare(
        _ id: FunctionID, of executable: IRExecutable, using lowering: SignatureLowering,
    ) -> DeclaredFunction {
        let function = executable.program.functions[id]
        // A name with parentheses is none that the runtime or the C library defines or calls.
        let name = id == executable.main ? "rayo.main" : function.name
        let signature = lowering.lower(FunctionSignature(of: function), in: context)
        let llvmFunction = module.addFunction(named: name, type: signature.type,
                                              parameterAttributes: signature.parameterAttributes)
        return DeclaredFunction(function: llvmFunction, signature: signature)
    }

    /// The runtime's `function`, which takes one argument of `type` and returns nothing, as a call passes it.
    private func runtimeFunction(
        _ function: Function, taking type: RayoType, using lowering: SignatureLowering,
    ) -> DeclaredFunction {
        let signature = lowering.lower(FunctionSignature(runtimeTaking: type), in: context)
        return DeclaredFunction(function: function, signature: signature)
    }
}
