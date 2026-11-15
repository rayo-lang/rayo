/// How a function takes the argument of one of its parameters, which decides what the function may do with it and
/// what its caller passes.
public enum ParameterConvention: String, Hashable, Sendable {
    /// The function reads the argument, which the caller keeps, and can't move it out or change it.
    case borrowed
    /// The function takes the argument, which the caller gives up, and the function must read it or move it on.
    case owned
    /// The function may change the argument in the caller's place, and the caller reads what the function leaves
    /// there.
    case mutable

    /// `type` as a parameter of this convention writes it: after `owned` or `mutable`, and on its own where the
    /// parameter borrows, as the source writes it.
    public func spelling(of type: RayoType) -> String {
        self == .borrowed ? "\(type)" : "\(rawValue) \(type)"
    }
}
