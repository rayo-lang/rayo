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
    /// Whether integer overflow panics, where otherwise it wraps.
    let checksOverflow: Bool

    /// Makes an empty module named `sourcePath`, configured to compile as `target` does.
    init(sourcePath: String, for target: borrowing TargetMachine, checksOverflow: Bool) {
        module = context.makeModule(named: sourcePath)
        builder = context.makeBuilder()
        target.configure(module)
        self.sourcePath = sourcePath
        self.checksOverflow = checksOverflow
    }

    /// Defines the program's functions in the module, its structs as named LLVM types, calling `runtime`'s
    /// functions where the program calls the runtime.
    func emit(_ executable: IRExecutable, calling runtime: RuntimeFunctions) {
        let program = executable.program
        let types = LLVMTypes(program.types, in: context)
        let functions = program.functions.indices.map { declare(FunctionID(index: $0), of: executable, using: types) }

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (function, llvmFunction) in zip(program.functions, functions) {
            var emitter = FunctionEmitter(function: function, into: llvmFunction, functions: functions, types: types,
                                          runtime: runtime)
            emitter.emit(in: self)
        }
    }

    /// Declares the function `id`: the program's `main` as `rayo.main`, which the runtime's C entry point runs, and
    /// any other function by its name and parameters, such as `f(_: Int)`.
    private func declare(_ id: FunctionID, of executable: IRExecutable, using types: LLVMTypes) -> Function {
        let function = executable.program.functions[id.index]
        // A name with parentheses is none that the runtime or the C library defines or calls.
        let name = id == executable.main ? "rayo.main" : function.name
        let parameters = function.locals.prefix(function.parameterCount).map { types.llvmType($0.type) }
        let type = context.functionType(returning: types.llvmType(function.result), taking: parameters)
        return module.addFunction(named: name, type: type)
    }
}
