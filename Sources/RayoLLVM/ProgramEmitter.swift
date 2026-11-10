internal import CLLVM
import RayoIR
import RayoSema

/// Emits a program into an LLVM module, calling the runtime's functions.
struct ProgramEmitter {
    let module: ModuleBuilder
    let runtime: Runtime
    let sourcePath: String
    let checksOverflow: Bool

    /// Defines the program's functions in the module.
    func emit(_ program: IRProgram) {
        let functions = program.functions.indices.map { declare(FunctionID(index: $0), of: program) }

        // Emit the bodies once every function is declared, so a body can call a function that comes after it.
        for (function, llvmFunction) in zip(program.functions, functions) {
            var emitter = FunctionEmitter(function: function, into: llvmFunction.value, functions: functions,
                                          program: self)
            emitter.emit()
        }
    }

    /// Declares the function `id`: the program's `main` as `rayo.main`, which the runtime's C entry point runs, and
    /// any other function by its name and parameters, such as `f(_: Int)`.
    private func declare(_ id: FunctionID, of program: IRProgram) -> FunctionValue {
        let function = program.functions[id.index]
        // A name with parentheses is none that the runtime or the C library defines or calls.
        let name = id == program.main ? "rayo.main" : function.name
        let parameters = function.locals.prefix(function.parameterCount).map { llvmType($0.type) }
        return module.addFunction(name, taking: parameters, returning: llvmType(function.result))
    }

    /// The LLVM type that holds a value of `type`.
    func llvmType(_ type: RayoType) -> LLVMTypeRef {
        switch type {
        case .int: return module.int64
        case .bool: return module.bool
        case .void: return module.void
        }
    }
}
