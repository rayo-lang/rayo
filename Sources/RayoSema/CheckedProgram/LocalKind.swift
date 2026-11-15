/// What declares a local, which decides whether it may change.
public enum LocalKind: Equatable, Sendable {
    /// A local assigned at most once on each path, its declaration's value included.
    case `let`
    /// A local assigned any number of times.
    case `var`
    /// A parameter, which holds the caller's argument as its convention takes it.
    case parameter(ParameterConvention)

    /// The word the program's text starts the local's declaration with.
    package var keyword: String {
        switch self {
        case .let: "let"
        case .var: "var"
        case .parameter: "param"
        }
    }

    /// `type` as the program's text declares the local with it: after the convention where the local is a parameter
    /// that doesn't borrow, and on its own otherwise.
    package func spelling(of type: RayoType) -> String {
        guard case .parameter(let convention) = self else { return "\(type)" }
        return convention.spelling(of: type)
    }
}
