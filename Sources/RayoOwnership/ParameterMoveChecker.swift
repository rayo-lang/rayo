import RayoDiagnostics
import RayoIR

/// Checks that a program moves no value out of a borrowed parameter, whose caller still owns the value.
public enum ParameterMoveChecker {
    /// Reports each move out of a borrowed parameter, or out of a field inside one, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.functions.flatMap { check(PlaceTypes(function: $0, types: program.types)) }.inSourceOrder
    }

    /// Checks every block of the function whose places `places` gives the types of, whether or not a path reaches it.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        places.function.blocks.flatMap(\.operands).compactMap { error(at: $0, in: places) }
    }

    /// The error at `operand` where it moves a value out of a borrowed parameter, or nil where it doesn't.
    private static func error(at operand: Operand, in places: PlaceTypes) -> Diagnostic? {
        // Only a move out of a borrowed parameter takes a value its caller owns, and a parameter, a local of the
        // source, names each place inside it.
        guard case .move(let place) = operand,
              case .source(let parameter, .parameter, _) = places.function.locals[place.local.index],
              let name = places.sourceName(of: place.local, fields: place.fields)
        else { return nil }

        // The error names the whole parameter, or the field moved out of it as the source writes it.
        let code: ErrorCode = place.fields.isEmpty
            ? .moveFromParameter(name: parameter) : .moveFieldFromParameter(field: name, parameter: parameter)
        return Diagnostic(code, at: place.range)
    }
}

private extension BasicBlock {
    /// The operands the block uses, its statements' in order and then its terminator's.
    var operands: [Operand] {
        let statementOperands = statements.flatMap { statement in
            switch statement {
            case .compute(_, let value, _): value.operands
            case .declare: [Operand]()
            }
        }
        return statementOperands + [terminator.operand].compactMap { $0 }
    }
}
