import RayoCheckedProgram

/// A function's result type, as its declaration gives it.
enum DeclaredResult {
    case type(RayoType)
    /// A written type that names no type, or one that `main` can't return, which was reported there.
    case failed
    /// A written type too large for the stack, which was reported there. The body still returns values of the type,
    /// so their own errors are reported, but the function fails, and no call takes its result.
    case tooLargeForStack(RayoType)
    /// None written, on a body that is a single expression, whose type is the result type.
    case givenByBody(FunctionID)

    /// Whether a written type failed.
    var hasFailed: Bool {
        switch self {
        case .failed, .tooLargeForStack: true
        case .type, .givenByBody: false
        }
    }

    /// The type, when the declaration alone gives it, which the body's returned values are checked against.
    var type: RayoType? {
        switch self {
        case .type(let type), .tooLargeForStack(let type): type
        // A written type that names no type, or a result that the body gives, has none.
        case .failed, .givenByBody: nil
        }
    }
}
