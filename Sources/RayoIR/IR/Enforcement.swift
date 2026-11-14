/// How the program makes sure that no access conflicts with another while it is live.
public enum Enforcement: Hashable, Sendable {
    /// The compiler proves it, so the access costs nothing when the program runs.
    case `static`
    /// The access takes a mark on its place when it begins and releases it when it ends, and an access that conflicts
    /// with a mark panics. Only an object's value takes one, since code the compiler can't see may reach an object.
    case dynamic
}
