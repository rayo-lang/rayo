import RayoSema

/// What each parameter convention means to the checks of this stage, which take it from here alone. Every parameter
/// holds its argument from the function's entry, whatever its convention.
extension ParameterConvention {
    /// Whether the caller reads the parameter's value at each return: only a mutable parameter's, since its caller
    /// reads what the function leaves in its place.
    var isReadAtReturn: Bool {
        self == .mutable
    }

    /// Whether the function's entry stores the parameter's value, which some code must then read, as it must read any
    /// other value stored: only an owned parameter's, which the function takes from its caller.
    var isStoredAtEntry: Bool {
        self == .owned
    }

    /// Whether the function may move the value out of the parameter: only an owned one, since a borrowed or mutable
    /// parameter's value is its caller's.
    var allowsMove: Bool {
        self == .owned
    }
}
