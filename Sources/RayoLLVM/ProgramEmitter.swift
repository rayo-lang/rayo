internal import CLLVM
import RayoIR
import RayoSema

/// Emits a program into an LLVM module, calling the runtime's functions.
struct ProgramEmitter {
    let module: ModuleBuilder
    let runtime: RuntimeFunctions
    let sourcePath: String
    let checksOverflow: Bool

    /// Defines the program's functions in the module, its structs as named LLVM types.
    func emit(_ executable: IRExecutable) {
        let program = executable.program
        let types = LLVMTypes(program.types, in: module)
        let functions = program.functions.indices.map { declare(FunctionID(index: $0), of: executable, using: types) }

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (function, llvmFunction) in zip(program.functions, functions) {
            var emitter = FunctionEmitter(function: function, into: llvmFunction.value, functions: functions,
                                          types: types, program: self)
            emitter.emit()
        }
    }

    /// Declares the function `id`: the program's `main` as `rayo.main`, which the runtime's C entry point runs, and
    /// any other function by its name and parameters, such as `f(_: Int)`.
    private func declare(_ id: FunctionID, of executable: IRExecutable, using types: LLVMTypes) -> FunctionValue {
        let function = executable.program.functions[id.index]
        // A name with parentheses is none that the runtime or the C library defines or calls.
        let name = id == executable.main ? "rayo.main" : function.name
        let parameters = function.locals.prefix(function.parameterCount).map { types.llvmType($0.type) }
        return module.addFunction(name, taking: parameters, returning: types.llvmType(function.result))
    }
}
