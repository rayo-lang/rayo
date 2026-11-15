import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Calls of the prelude's built-ins.
extension FunctionEmitter {
    /// Emits a call of `builtin` with `arguments`, which the source makes at `range`, and stores its result in
    /// `destination` when there is one. Throws where the runtime lacks the function that the built-in calls.
    func call(
        _ builtin: Builtin, passing arguments: [CallArgument], into destination: Place?, at range: SourceRange,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch builtin {
        // A conversion between the integer types runs in place, with no call.
        case .conversion(let source, let target):
            try convert(arguments[0], from: source, to: target, into: destination, at: range, in: program)

        // The runtime prints a value of each scalar type with a C function named for the type, whose convention
        // passes a lone integer or Bool directly, as Rayo's does.
        case .print(let scalar):
            try callRuntime("rayo.print_\(scalar.name.lowercased())", in: .rayo, for: builtin, passing: arguments,
                            into: destination, in: program)
        }
    }

    /// Emits the conversion of `argument`, an integer of type `source`, to the integer type `target`, which the source
    /// makes at `range`, and stores the converted value in `destination` when there is one.
    private func convert(
        _ argument: CallArgument, from source: ScalarType, to target: ScalarType, into destination: Place?,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        let integer = whole(value(of: argument, with: program.builder), with: program.builder)
        let converted = try operators.emitConversion(of: integer, from: source, to: target, at: range, in: program)
        keep(converted, in: destination, with: program.builder)
    }

    /// Emits a call, in `convention`, of the runtime's function `symbol`, which takes `builtin`'s parameters and gives
    /// its result.
    private func callRuntime(
        _ symbol: String, in convention: CallingConvention, for builtin: Builtin, passing arguments: [CallArgument],
        into destination: Place?, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        let function = try program.runtimeFunction(named: symbol)
        let signature = FunctionSignature(of: builtin, convention: convention)
        let target = DeclaredFunction(function: function, signature: lowering.lower(signature, in: program.context))
        call(target, passing: arguments, into: destination, with: program.builder)
    }
}
