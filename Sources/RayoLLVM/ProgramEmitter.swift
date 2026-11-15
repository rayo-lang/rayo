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

    /// Defines the program's functions in the module, its structs as named LLVM types. `executable` must keep the
    /// IR's types.
    func emit(_ executable: IRExecutable) {
        let program = executable.program
        let lowering = SignatureLowering(types: LLVMTypes(program.types, in: context))
        let runtimeFunctions = RuntimeFunctions(lowering: lowering, in: context)
        let callTargets = program.functions.ids.map { target(of: $0, in: executable, using: lowering) }

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (id, body) in program.definedFunctions {
            // Only a function the source writes has a body, and the module declares each such function.
            guard case .function(let declared) = callTargets[id.index] else {
                preconditionFailure("a primary initializer has no body")
            }
            var emitter = FunctionEmitter(body: body, of: program.functions[id], into: declared,
                                          callTargets: callTargets, lowering: lowering,
                                          runtimeFunctions: runtimeFunctions, in: self)
            emitter.emit(in: self)
        }
    }

    /// What a call of the function `id` reaches: a function the module declares for it, or, for a primary
    /// initializer, the struct its calls build in place.
    private func target(
        of id: FunctionID, in executable: IRExecutable, using lowering: SignatureLowering,
    ) -> CallTarget {
        switch executable.program.functions[id].kind {
        case .written: .function(declare(id, of: executable, using: lowering))
        case .primaryInitializer(let structID): .primaryInitializer(structID)
        }
    }

    /// Declares the function `id`: the program's `main` as the runtime function that the runtime's C entry point runs,
    /// and any other function by its name and parameters, such as `f(_: Int)`.
    private func declare(
        _ id: FunctionID, of executable: IRExecutable, using lowering: SignatureLowering,
    ) -> DeclaredFunction {
        let function = executable.program.functions[id]
        // A name with parentheses is none that the runtime or the C library defines or calls.
        let name = id == executable.main ? RuntimeFunction.main.symbol : function.name
        let signature = lowering.lower(FunctionSignature(of: function), in: context)
        let llvmFunction = module.addFunction(named: name, type: signature.type,
                                              parameterAttributes: signature.parameterAttributes)
        return DeclaredFunction(function: llvmFunction, signature: signature)
    }
}
