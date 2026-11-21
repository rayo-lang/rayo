import RayoCheckedProgram
import RayoDiagnostics
import RayoIR

/// Checks that a program moves no value out of a place that can't give it up: a parameter whose value is its caller's,
/// or an array's element, which its array holds for as long as the array holds a value.
enum MoveChecker {
    /// Reports each move out of a parameter whose value is its caller's, out of an array's element, or out of a part
    /// inside either, in every block of the body whose places `places` gives the types of, whether or not a path
    /// reaches it.
    static func errors(in places: PlaceTypes) -> [Diagnostic] {
        places.body.blocks.flatMap { $0.effects.joined() }.compactMap { error(at: $0, in: places) }
    }

    /// The error at `effect` where it moves a value out of a place that can't give it up, or nil where it doesn't.
    private static func error(at effect: Effect, in places: PlaceTypes) -> Diagnostic? {
        // Only a move takes a value out of its place.
        guard case .move(let place, let range) = effect else { return nil }

        // An element, wherever its array lies, is the array's for as long as the array holds a value.
        if let innermost = place.steps.lastIndex(where: \.isElement) {
            let part = part(of: place, innermostElementAt: innermost, in: places)
            return Diagnostic(.moveFromElement(part: part), at: range)
        }

        // A parameter that doesn't own its value can't give it up.
        guard case .source(let parameter, .parameter(let convention), _, _) = places.body.locals[place.root.index],
              !convention.allowsMove else { return nil }

        // A parameter is a local of the source, which names each place inside it.
        guard let name = places.sourceName(of: place) else {
            preconditionFailure("a parameter is a local of the source")
        }

        // The error names the whole parameter, or the part moved out of it as the source writes it.
        let code: ErrorCode = place.steps.isEmpty
            ? .moveFromParameter(name: parameter) : .moveFieldFromParameter(field: name, parameter: parameter)
        return Diagnostic(code, at: range)
    }

    /// What `place` takes out of an element, named by the innermost array that the source names on the way to it. Its
    /// innermost element is at step `innermost`.
    private static func part(
        of place: Place, innermostElementAt innermost: Int, in places: PlaceTypes,
    ) -> ElementPart {
        // The source names an array only up to its first element at an index a local holds, so that element is the
        // one named where there is one.
        let depth = place.steps.firstIndex(where: \.isAtIndexInLocal) ?? innermost
        let array = places.sourceName(of: place.prefix(depth))

        // The place is the element, or a part inside it that the source writes from the element where it can.
        let taken: ElementPart.Taken =
            if depth + 1 == place.steps.count { .element }
            else if let name = places.partName(of: place, after: depth + 1) { .named(name) }
            else { .unnamed }
        return ElementPart(taken, of: array)
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

    /// Whether the step leads into an array's element at an index a local holds.
    var isAtIndexInLocal: Bool {
        switch self {
        case .field, .element: false
        case .elementAt: true
        }
    }
}
