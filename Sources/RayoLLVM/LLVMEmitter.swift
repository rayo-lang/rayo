internal import CLLVM
import RayoIR
import RayoSema

/// Compiles Rayo IR to object code for the host, through LLVM.
public enum LLVMEmitter {
    /// The object code of `program` and the program runtime, whose panics name `sourcePath` as the file they
    /// happen in, ready to link into an executable for the host. Integer overflow panics where `checksOverflow` is
    /// true, and wraps where it's false; `optimizes` runs LLVM's optimisations over the module.
    public static func objectCode(for program: IRProgram, sourcePath: String, checksOverflow: Bool,
                                  optimizes: Bool) throws(LLVMError) -> [UInt8] {
        let target = try TargetMachine(optimizes: optimizes)
        let module = ModuleBuilder(named: sourcePath, for: target)
        let runtime = try Runtime(in: module)

        ProgramEmitter(module: module, runtime: runtime, sourcePath: sourcePath, checksOverflow: checksOverflow)
            .emit(program)
        try runtime.link(into: module)
        module.hideDefinitions(except: Runtime.entryPoint)
        try module.verify()
        let objectCode = try target.objectCode(of: module)

        try module.checkReportedErrors()
        return objectCode
    }
}

/// A fault in `rayoc`, or in the LLVM it compiles with, that stops LLVM compiling a program: never one in the
/// program itself.
public struct LLVMError: Error {
    public var message: String
}

/// Emits a program into an LLVM module, calling the runtime's functions.
struct ProgramEmitter {
    let module: ModuleBuilder
    let runtime: Runtime
    let sourcePath: String
    let checksOverflow: Bool

    /// Defines the program's functions, each before any body calls it.
    func emit(_ program: IRProgram) {
        let functions = program.functions.indices.map { declare(FunctionID(index: $0), of: program) }
        for (function, llvmFunction) in zip(program.functions, functions) {
            var emitter = FunctionEmitter(function: function, into: llvmFunction.value, functions: functions, program: self)
            emitter.emit()
        }
    }

    /// Declares the function `id`. The program's `main` is `rayo.main`, which the runtime's C entry point runs. Each
    /// other function is named as the program names it, with its parentheses, so it takes no name the runtime or
    /// the C library defines or calls, none of which holds a parenthesis.
    private func declare(_ id: FunctionID, of program: IRProgram) -> FunctionValue {
        let function = program.functions[id.index]
        let name = id == program.main ? "rayo.main" : function.name
        let parameters = function.locals.prefix(function.parameterCount).map(llvmType)
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
