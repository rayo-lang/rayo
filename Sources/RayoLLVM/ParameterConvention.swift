/// What a function may do with the argument of one of its parameters.
enum ParameterConvention {
    /// The function reads the argument, which the caller keeps.
    case borrowed
    /// The function takes the argument, which the caller gives up.
    case owned
    /// The function may change the argument, in the caller's place.
    case mutable
}
