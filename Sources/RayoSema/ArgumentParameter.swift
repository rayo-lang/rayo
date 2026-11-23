import RayoCheckedProgram

/// The parameter that a call's argument is given to, as checking how the argument gives a place needs it: the name
/// the call writes for the function or type it calls, and how the parameter takes its argument. A parameter that
/// borrows is lent a place, written `&p` or bare, and one that owns its argument takes a place written bare.
struct ArgumentParameter {
    /// The name the call writes for what it calls, such as `show`, `Enemy` or `.init`, for an error to name it by.
    var callee: String
    var convention: ParameterConvention
}
