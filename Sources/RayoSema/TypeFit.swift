/// Whether a typed value can stand where a position expects a type, and the value as it stands there. This is the
/// one place that decides it: a value fits only its own type, and stands there as it is.
enum TypeFit {
    /// Whether a value of `type` can stand where a position expects `expected`.
    static func fits(_ type: RayoType, _ expected: RayoType) -> Bool {
        type == expected
    }

    /// `value` as it stands where a position expects `expected`, or nil where it can't stand there.
    static func fitted(_ value: CheckedExpr, to expected: RayoType) -> CheckedExpr? {
        fits(value.type, expected) ? value : nil
    }
}
