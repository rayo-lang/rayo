import RayoCheckedProgram

/// What each parameter convention means to this stage's checks of what a function stores and reads, which take it
/// from here alone; `MoveSource` says which parameters may be moved out of. Every parameter holds its argument from
/// the function's entry, whatever its convention.
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
}
