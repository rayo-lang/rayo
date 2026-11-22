import RayoCheckedProgram
import RayoDiagnostics

/// What a position expects of the value that stands in it: its type, the error a value of another type reports
/// there, and, where the position is a call's argument, the parameter that takes it, which says how a place given to
/// it is written.
struct Expectation {
    let type: RayoType
    /// The error at a value of the type `found`, where the position expects `expected`.
    let mismatch: (_ expected: TypeName, _ found: TypeName) -> ErrorCode
    /// The parameter the position is the argument of, or nil where it is no call's argument.
    let parameter: ArgumentParameter?

    init(_ type: RayoType, parameter: ArgumentParameter? = nil,
         mismatch: @escaping (TypeName, TypeName) -> ErrorCode = ErrorCode.typeMismatch) {
        self.type = type
        self.parameter = parameter
        self.mismatch = mismatch
    }
}
