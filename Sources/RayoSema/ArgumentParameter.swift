import RayoCheckedProgram

/// The parameter a call's argument is given to, as checking how the argument gives a place needs it.
struct ArgumentParameter {
    /// The name the call writes for what it calls, such as `show`, `Enemy` or `.init`, for an error to name it by.
    var callee: String
    var convention: ParameterConvention
    /// Whether a bare value that no local holds may be lent to the parameter as a temporary.
    var borrowsTemporaries: Bool
}
