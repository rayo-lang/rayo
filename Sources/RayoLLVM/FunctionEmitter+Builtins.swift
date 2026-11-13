import LLVM
import RayoIR
import RayoSema

/// Calls of the prelude's built-ins, each emitted as a call into the runtime or as code in place.
extension FunctionEmitter {
    /// Emits a call of `builtin` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the arguments aren't of the types `builtin` takes, or the result isn't of the destination's.
    func call(
        _ builtin: Builtin, passing operands: [Operand], into destination: Place?,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch builtin {
        case .printInt:
            try callRuntime("rayo.print_int", for: builtin, passing: operands, into: destination, in: program)
        case .printBool:
            try callRuntime("rayo.print_bool", for: builtin, passing: operands, into: destination, in: program)
        }
    }

    /// Emits a call of the runtime's function `symbol`, which takes `builtin`'s parameters and gives its result.
    private func callRuntime(
        _ symbol: String, for builtin: Builtin, passing operands: [Operand], into destination: Place?,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        let function = try program.runtimeFunction(named: symbol)
        let signature = lowering.lower(FunctionSignature(of: builtin), in: program.context)
        let target = DeclaredFunction(function: function, signature: signature)
        try call(target, passing: operands, into: destination, with: program.builder)
    }
}
