/// How a function takes the argument of one of its parameters, which decides what the function may do with it and
/// what its caller passes.
public enum ParameterConvention: Hashable, Sendable {
    /// The function reads the argument, which the caller keeps, and can't move it out or change it.
    case borrowed
    /// The function takes the argument, which the caller gives up, and the function must read it or move it on.
    case owned
    /// The function may change the argument in the caller's place, and the caller reads what the function leaves
    /// there.
    case mutable

    /// `type` as the source declares a parameter of this convention with it, after the reference the parameter takes,
    /// such as `&Enemy`: after `&` where the parameter borrows, after `mutable &` where it borrows for change, and on
    /// its own where it owns its argument.
    public func spelling(of type: RayoType) -> String {
        reference + "\(type)"
    }

    /// The reference the source writes before a parameter's type, such as `&`, or nothing where the parameter owns its
    /// argument.
    public var reference: String {
        switch self {
        case .borrowed: "&"
        case .owned: ""
        case .mutable: "mutable &"
        }
    }
}
