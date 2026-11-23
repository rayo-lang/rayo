/// How a parameter takes its argument, when it doesn't own it: the reference its type is written as.
public enum ParamConvention: String, Sendable {
    /// `&T`, which borrows the argument.
    case borrowed = "&"
    /// `mutable &T`, which borrows it for change.
    case mutable = "mutable &"
}
