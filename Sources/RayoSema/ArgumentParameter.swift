import RayoCheckedProgram

/// The parameter a call's argument is given to, as checking how the argument gives a place needs it.
struct ArgumentParameter {
    /// The name the call writes for what it calls, such as `show`, `Enemy` or `.init`, for an error to name it by.
    var callee: String
    var convention: ParameterConvention
    /// Whether a bare value that no local holds may be lent to the parameter as a temporary.
    var borrowsTemporaries: Bool
    /// What the parameter, where it owns its argument, does with a bare place of a type that isn't implicitly copyable.
    var barePlaceUse: BarePlaceUse
    /// Whether a function of the callee's name, among those whose labels and types the call's arguments fit, borrows
    /// the argument, so that a `&` of it reaches that function.
    var isBorrowedByOverload: Bool
}
