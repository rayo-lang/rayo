import LLVM
import RayoIR
import RayoSema

/// Calls of the prelude's built-ins.
extension FunctionEmitter {
    /// Emits a call of `builtin` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the runtime lacks the function that the built-in calls.
    func call(
        _ builtin: Builtin, passing operands: [Operand], into destination: Place?,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch builtin {
        // The runtime's prints are C functions, whose convention passes a lone Int or Bool directly, as Rayo's does.
        case .printInt:
            try callRuntime("rayo.print_int", in: .rayo, for: builtin, passing: operands, into: destination,
                            in: program)
        case .printBool:
            try callRuntime("rayo.print_bool", in: .rayo, for: builtin, passing: operands, into: destination,
                            in: program)
        }
    }

    /// Emits a call, in `convention`, of the runtime's function `symbol`, which takes `builtin`'s parameters and gives
    /// its result.
    private func callRuntime(
        _ symbol: String, in convention: CallingConvention, for builtin: Builtin, passing operands: [Operand],
        into destination: Place?, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        let function = try program.runtimeFunction(named: symbol)
        let signature = FunctionSignature(of: builtin, convention: convention)
        let target = DeclaredFunction(function: function, signature: lowering.lower(signature, in: program.context))
        call(target, passing: operands, into: destination, with: program.builder)
    }
}
