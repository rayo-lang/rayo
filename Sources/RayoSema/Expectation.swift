import RayoDiagnostics

/// The type a position expects of the value that stands in it, and the error a value of another type reports there.
struct Expectation {
    let type: RayoType
    /// The error at a value of the type `found`, where the position expects `expected`.
    let mismatch: (_ expected: TypeName, _ found: TypeName) -> ErrorCode

    init(_ type: RayoType, mismatch: @escaping (TypeName, TypeName) -> ErrorCode = ErrorCode.typeMismatch) {
        self.type = type
        self.mismatch = mismatch
    }
}
