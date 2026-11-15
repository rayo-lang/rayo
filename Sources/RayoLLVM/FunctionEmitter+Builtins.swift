import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Calls of the prelude's built-ins.
extension FunctionEmitter {
    /// Emits a call of `builtin` with `arguments`, which the source makes at `range`, and stores its result in
    /// `destination` when there is one.
    func call(
        _ builtin: Builtin, passing arguments: [CallArgument], into destination: Place?, at range: SourceRange,
        in program: borrowing ProgramEmitter,
    ) {
        switch builtin {
        // A conversion between the integer types runs in place, with no call.
        case .conversion(let source, let target):
            convert(arguments[0], from: source, to: target, into: destination, at: range, in: program)

        // The runtime prints a value of each scalar type with a function of its own.
        case .print(let scalar):
            call(runtimeFunctions.print(scalar, in: program.module), passing: arguments, into: destination,
                 with: program.builder)
        }
    }

    /// Emits the conversion of `argument`, an integer of type `source`, to the integer type `target`, which the source
    /// makes at `range`, and stores the converted value in `destination` when there is one.
    private func convert(
        _ argument: CallArgument, from source: ScalarType, to target: ScalarType, into destination: Place?,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) {
        let integer = whole(value(of: argument, with: program.builder), with: program.builder)
        let converted = operators.emitConversion(of: integer, from: source, to: target, at: range, in: program)
        keep(converted, in: destination, with: program.builder)
    }
}
