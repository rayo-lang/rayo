import LLVM
import RayoIR
import RayoSema

/// Calls of the prelude's built-ins.
extension FunctionEmitter {
    /// Emits a call of `builtin` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the arguments aren't of the types `builtin` takes, or the result isn't of the destination's.
    func call(
        _ builtin: Builtin, passing operands: [Operand], into destination: Place?,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        // Each built-in is the runtime's function of a symbol, called in a convention. The runtime's prints are C
        // functions, whose convention passes a lone Int or Bool directly, as Rayo's does.
        let (symbol, convention): (String, CallingConvention) = switch builtin {
        case .printInt: ("rayo.print_int", .rayo)
        case .printBool: ("rayo.print_bool", .rayo)
        }

        // Call the runtime's function as the built-in's signature says, in that convention.
        let function = try program.runtimeFunction(named: symbol)
        let signature = FunctionSignature(of: builtin, convention: convention)
        let target = DeclaredFunction(function: function, signature: lowering.lower(signature, in: program.context))
        try call(target, passing: operands, into: destination, with: program.builder)
    }
}
