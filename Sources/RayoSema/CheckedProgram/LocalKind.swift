/// What declares a local, which decides whether it may change.
public enum LocalKind: Sendable {
    /// A local assigned at most once on each path, its declaration's value included.
    case `let`
    /// A local assigned any number of times.
    case `var`
    /// A borrowed parameter, which holds the caller's argument.
    case parameter
}
