import RayoSource

/// A place the source names: a local, or a value that no local holds, and the steps the source takes into it, such as
/// `e.stats.hp`.
public struct CheckedPlace: Sendable {
    public var root: CheckedPlaceRoot
    /// The steps from the root to the place, outermost first; none where the place is the root itself.
    public var steps: [CheckedPlaceStep] = []

    /// Where the source names the whole place.
    public var range: SourceRange {
        switch steps.last {
        case .field(_, let range)?: range
        case nil: root.range
        }
    }

    /// The place that `step` leads to from this one.
    func appending(_ step: CheckedPlaceStep) -> CheckedPlace {
        CheckedPlace(root: root, steps: steps + [step])
    }
}

/// What a place starts from.
public enum CheckedPlaceRoot: Sendable {
    /// A local, which the source names at `range`.
    case local(LocalID, range: SourceRange)
    /// A value that no local holds, such as a call's result, which lowering holds in a temporary.
    case temporary(CheckedExpr)

    /// Where the source names the root.
    public var range: SourceRange {
        switch self {
        case .local(_, let range): range
        case .temporary(let value): value.range
        }
    }
}

/// A step from a place to a part of the value it holds.
public enum CheckedPlaceStep: Sendable {
    /// Steps into a struct's field, by its place in its struct's declaration. The source names the place the step
    /// leads to at `range`, from the root through the field's name.
    case field(Int, range: SourceRange)
}
