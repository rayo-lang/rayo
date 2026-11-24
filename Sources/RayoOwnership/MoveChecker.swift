import RayoCheckedProgram
import RayoDiagnostics
import RayoIR

/// Checks that a program moves no value out of a place that can't give it up: a parameter whose value is its caller's,
/// a `ref let`, whose value is the place's it refers to, or an array's element, which its array holds for as long
/// as the array holds a value.
enum MoveChecker {
    /// Reports each move out of a parameter whose value is its caller's, out of a `ref let`, out of an array's
    /// element, or out of a part inside any of them, in every block of the body whose places `places` gives the types
    /// of, whether or not a path reaches it.
    static func errors(in places: PlaceTypes) -> [Diagnostic] {
        var errors: [Diagnostic] = []
        for block in places.body.blocks {
            block.forEachEffect { effect in
                if let diagnostic = error(at: effect, in: places) { errors.append(diagnostic) }
            }
        }
        return errors
    }

    /// The error at `effect` where it moves a value out of a place that can't give it up, or nil where it doesn't.
    private static func error(at effect: Effect, in places: PlaceTypes) -> Diagnostic? {
        // Only a move takes a value out of its place, and one out of a place that can give its value up is allowed.
        guard case .move(let place, let range) = effect else { return nil }
        let root = places.body.locals[place.root.index]
        let source = MoveSource(local: root.sourceKind, liesInElement: place.steps.contains(where: \.isElement))
        guard !source.allowsMove else { return nil }

        // The error names an element by the array it lies in.
        if let innermost = place.steps.lastIndex(where: \.isElement) {
            let part = part(of: place, innermostElementAt: innermost, in: places)
            return Diagnostic(.moveFromElement(part: part), at: range)
        }

        // Any other place that can't give its value up lies in a local of the source that doesn't own its value.
        guard case .source(let local, let kind, _, _) = root, let name = places.sourceName(of: place) else {
            preconditionFailure("a temporary owns its value, and a local of the source names each place inside it")
        }

        // The error names the whole local, or the part moved out of it as the source writes it.
        let part = place.steps.isEmpty ? nil : name
        return Diagnostic(code(movingOutOf: local, of: kind, part: part), at: range)
    }

    /// The error for a move out of the local `local` of `kind`, which doesn't own its value, or out of `part` of it
    /// where that is given.
    private static func code(movingOutOf local: String, of kind: LocalKind, part: String?) -> ErrorCode {
        switch kind {
        // A parameter that doesn't own its value can't give it up.
        case .parameter:
            part.map { .moveFieldFromParameter(field: $0, parameter: local) } ?? .moveFromParameter(name: local)
        // Nor can a `ref let`, whose value is the place's it refers to.
        case .refLet:
            part.map { .moveFieldFromReference(field: $0, local: local) } ?? .moveFromReference(name: local)
        case .let, .var:
            preconditionFailure("a 'let' or a 'var' owns its value")
        }
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

private extension IRLocal {
    /// The kind the source declares the local with, or nil where lowering adds it as a temporary.
    var sourceKind: LocalKind? {
        switch self {
        case .source(_, let kind, _, _): kind
        case .temporary: nil
        }
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
