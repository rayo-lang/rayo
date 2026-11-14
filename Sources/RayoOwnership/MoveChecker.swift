import RayoDiagnostics
import RayoIR
import RayoSema

/// Checks that a program moves no value out of a place that can't give it up: a borrowed parameter, whose caller
/// still owns the value, or an array's element, which its array holds for as long as the array holds a value.
public enum MoveChecker {
    /// Reports each move out of a borrowed parameter, out of an array's element, or out of a part inside either,
    /// under the ID of each function that makes any, in source order.
    public static func check(_ program: IRProgram) -> [FunctionID: [Diagnostic]] {
        program.errors { check(PlaceTypes(body: $1, types: program.types)) }
    }

    /// Checks every block of the body whose places `places` gives the types of, whether or not a path reaches it.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        places.body.blocks.flatMap(\.operands).compactMap { error(at: $0, in: places) }
    }

    /// The error at `operand` where it moves a value out of a place that can't give it up, or nil where it doesn't.
    private static func error(at operand: Operand, in places: PlaceTypes) -> Diagnostic? {
        // Only a move takes a value out of its place.
        guard case .move(let place, let range) = operand else { return nil }

        // An element, wherever its array lies, is the array's for as long as the array holds a value.
        if place.steps.contains(where: \.isElement) { return Diagnostic(.moveFromElement, at: range) }

        // A borrowed parameter's value is its caller's.
        guard case .source(let parameter, .parameter, _) = places.body.locals[place.root.index] else { return nil }

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

private extension PlaceStep {
    /// Whether the step leads into an array's element.
    var isElement: Bool {
        switch self {
        case .field: false
        case .element, .elementAt: true
        }
    }
}
