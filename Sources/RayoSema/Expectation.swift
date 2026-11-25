import RayoCheckedProgram
import RayoDiagnostics

/// What a position expects of the value that stands in it: its type, the error a value of another type reports
/// there, and the position itself, which decides what happens to a place given to it.
struct Expectation {
    let type: RayoType
    /// The error at a value of the type `found`, where the position expects `expected`.
    let mismatch: (_ expected: TypeName, _ found: TypeName) -> ErrorCode
    let position: Position

    init(_ type: RayoType, at position: Position,
         mismatch: @escaping (TypeName, TypeName) -> ErrorCode = ErrorCode.typeMismatch) {
        self.type = type
        self.position = position
        self.mismatch = mismatch
    }
}
