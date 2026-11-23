import RayoCheckedProgram
import RayoDiagnostics

/// What a position expects of the value that stands in it: its type, the error a value of another type reports
/// there, and, where the position is a call's argument or a declaration's value, what takes the value, which says how
/// a place given to it is written.
struct Expectation {
    let type: RayoType
    /// The error at a value of the type `found`, where the position expects `expected`.
    let mismatch: (_ expected: TypeName, _ found: TypeName) -> ErrorCode
    /// What takes the value, or nil where the position is neither a call's argument nor a declaration's value.
    let recipient: Recipient?

    init(_ type: RayoType, recipient: Recipient? = nil,
         mismatch: @escaping (TypeName, TypeName) -> ErrorCode = ErrorCode.typeMismatch) {
        self.type = type
        self.recipient = recipient
        self.mismatch = mismatch
    }
}
