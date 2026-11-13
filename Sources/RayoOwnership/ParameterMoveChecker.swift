import RayoDiagnostics
import RayoIR

/// Checks that a program moves no value out of a borrowed parameter, whose caller still owns the value.
public enum ParameterMoveChecker {
    /// Reports each move out of a borrowed parameter, or out of a field inside one, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.definedFunctions.flatMap { check(PlaceTypes(body: $0.body, types: program.types)) }.inSourceOrder
    }

    /// Checks every block of the body whose places `places` gives the types of, whether or not a path reaches it.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        places.body.blocks.flatMap(\.operands).compactMap { error(at: $0, in: places) }
    }

    /// The error at `operand` where it moves a value out of a borrowed parameter, or nil where it doesn't.
    private static func error(at operand: Operand, in places: PlaceTypes) -> Diagnostic? {
        // Only a move out of a borrowed parameter takes a value its caller owns.
        guard case .move(let place, let range) = operand,
              case .source(let parameter, .parameter, _) = places.body.locals[place.root.index]
        else { return nil }

        // A parameter is a local of the source, which names each place inside it.
        guard let name = places.sourceName(of: place) else {
            preconditionFailure("a parameter is a local of the source")
        }

        // The error names the whole parameter, or the part moved out of it as the source writes it.
        let code: ErrorCode = place.steps.isEmpty
            ? .moveFromParameter(name: parameter) : .moveFieldFromParameter(field: name, parameter: parameter)
        return Diagnostic(code, at: range)
    }
}
