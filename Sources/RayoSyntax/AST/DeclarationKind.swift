/// What the words that start a local's declaration say about its bindings: whether each owns a value or refers to a
/// place, and whether it may change. Each kind's raw value is those words, as the source writes them.
public enum DeclarationKind: String, Sendable, Hashable {
    /// `let`, which owns a value it can't change.
    case `let` = "let"
    /// `var`, which owns a value it may change.
    case `var` = "var"
    /// `ref let`, which refers to a place, read-only.
    case refLet = "ref let"
    /// `ref var`, which refers to a place that may change through it.
    case refVar = "ref var"

    /// Whether the bindings refer to a place, so each needs one to refer to.
    var refersToPlace: Bool {
        switch self {
        case .refLet, .refVar: true
        case .let, .var: false
        }
    }
}
