import LLVM
import RayoIR
import RayoSema

/// Emits a program into an LLVM module of its own, which it owns with the context the module is made in, the builder
/// that adds to it, and the runtime its code calls.
struct ProgramEmitter: ~Copyable {
    let context = Context()
    let module: Module
    let builder: Builder
    /// The path of the program's source, which a panic names as the file it happens in.
    let sourcePath: String
    /// The build the program's code is emitted for.
    let build: Build
    private let runtime: Runtime

    /// Makes an empty module named `sourcePath`, configured to compile as `target` does, with the runtime parsed
    /// beside it.
    init(sourcePath: String, for target: borrowing TargetMachine, build: Build) throws(LLVMError) {
        module = context.makeModule(named: sourcePath)
        builder = context.makeBuilder()
        target.configure(module)
        runtime = try Runtime(in: context, for: module)
        self.sourcePath = sourcePath
        self.build = build
    }

    /// Ends the emitter, handing on the module it emitted into, with the runtime left out.
    consuming func takeModule() -> Module {
        module
    }

    /// Ends the emitter, handing on the module it emitted into, with the runtime linked in.
    consuming func linkedModule() throws(LLVMError) -> Module {
        try runtime.link(into: module)
        return module
    }

    /// The runtime's function `symbol`, declared in the module. Throws where the runtime defines no such function.
    func runtimeFunction(named symbol: String) throws(LLVMError) -> Function {
        try runtime.function(named: symbol, in: module)
    }

    /// Defines the program's functions in the module, its structs as named LLVM types. Throws where the IR gives an
    /// instruction a value of a type it doesn't take.
    func emit(_ executable: IRExecutable) throws(LLVMError) {
        let program = executable.program
        let lowering = SignatureLowering(types: LLVMTypes(program.types, in: context))
        let functions = program.functions.ids.map { declare($0, of: executable, using: lowering) }

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (id, body) in program.definedFunctions {
            var emitter = FunctionEmitter(body: body, of: program.functions[id], into: functions[id.index],
                                          functions: functions, lowering: lowering, in: self)
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
}
