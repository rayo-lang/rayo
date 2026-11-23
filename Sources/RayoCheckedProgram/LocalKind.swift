/// What declares a local, which decides whether it may change.
public enum LocalKind: Equatable, Sendable {
    /// A local assigned at most once on each path, its declaration's value included.
    case `let`
    /// A `ref let`, which borrows a place read-only: it sees the place's value without owning it, so it gives up no
    /// value, and the place can't change or move while the local is used.
    case refLet
    /// A local assigned any number of times.
    case `var`
    /// A parameter, which holds the caller's argument as its convention takes it.
    case parameter(ParameterConvention)

    /// The word the program's text starts the local's declaration with.
    package var keyword: String {
        switch self {
        case .let: "let"
        case .refLet: "ref"
        case .var: "var"
        case .parameter: "param"
        }
    }

    /// Whether the local holds a reference to a place, not a value of its own: a `ref let`, or a parameter that borrows
    /// its argument, for change or not. The local's own type is then a reference to the type of what it refers to.
    package var holdsReference: Bool {
        switch self {
        case .refLet, .parameter(.borrowed), .parameter(.mutable): true
        case .let, .var, .parameter(.owned): false
        }
    }

    /// `type` as the source declares the local with it: after the reference a parameter takes where the local is one
    /// that borrows its argument, and on its own otherwise.
    package func spelling(of type: RayoType) -> String {
        guard case .parameter(let convention) = self else { return "\(type)" }
        return convention.spelling(of: type)
    }
}
