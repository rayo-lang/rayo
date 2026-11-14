/// A function's result type, as its declaration gives it.
enum DeclaredResult {
    case type(RayoType)
    /// A written type that names no type, or one that `main` can't return, which was reported there.
    case failed
    /// None written, on a body that is a single expression, whose type is the result type.
    case givenByBody(FunctionID)

    /// Whether a written type failed.
    var hasFailed: Bool {
        if case .failed = self { true } else { false }
    }

    /// The type, when the declaration alone gives it.
    var type: RayoType? {
        // A result that failed, or that the body gives, has none.
        guard case .type(let type) = self else { return nil }
        return type
    }
}
