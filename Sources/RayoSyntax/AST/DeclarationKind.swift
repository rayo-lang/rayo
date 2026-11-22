/// What the words that start a local's declaration say about its bindings: whether each owns a value or refers to a
/// place, and whether it may change.
public enum DeclarationKind: Sendable, Hashable {
    /// `let`, which owns a value it can't change.
    case `let`
    /// `var`, which owns a value it may change.
    case `var`
    /// `ref let`, which refers to a place, read-only.
    case refLet
    /// `ref var`, which refers to a place that may change through it.
    case refVar

    /// Whether the bindings refer to a place, so each needs one to refer to.
    var refersToPlace: Bool {
        switch self {
        case .refLet, .refVar: true
        case .let, .var: false
        }
    }
}
