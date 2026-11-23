/// A function of the prelude whose code the compiler gives, in place of a body written in Rayo. Each built-in takes
/// scalar types, so a new scalar type gets its built-ins from `allCases` with no new case.
public enum Builtin: CaseIterable, Hashable, Sendable {
    /// `print(_: &T)`, which writes the value and a newline to standard output: an integer in decimal, and a Bool as
    /// `true` or `false`.
    case print(ScalarType)
    /// `T(_: U)`, which gives a value of the type `from`, `U`, as a value of the type `to`, `T`. A value that `to`
    /// can't hold panics where overflow checks are on, and keeps the low bits that fit where they are off.
    case conversion(from: ScalarType, to: ScalarType)

    /// Every built-in the prelude declares: a `print` of each scalar type, then each type's conversions, from each
    /// type in turn.
    public static var allCases: [Builtin] {
        ScalarType.prelude.map(Builtin.print) + ScalarType.prelude.flatMap(conversions(to:))
    }

    /// The conversions to `target`, from each scalar type it converts from.
    private static func conversions(to target: ScalarType) -> [Builtin] {
        ScalarType.prelude.filter(target.converts(from:)).map { .conversion(from: $0, to: target) }
    }

    /// Where the built-in's name lives in the prelude.
    package var name: BuiltinName {
        switch self {
        case .print: .function("print")
        case .conversion(_, let target): .initializer(of: .scalar(target))
        }
    }

    /// The prelude type the built-in initializes, or nil where it is no initializer.
    package var initializedType: RayoType? {
        guard case .initializer(let type) = name else { return nil }
        return type
    }

    /// The parameters, in order, each an unlabeled scalar: a print borrows its argument, and a conversion owns it.
    public var parameters: [FunctionParameter] {
        switch self {
        case .print(let scalar):
            [FunctionParameter(label: nil, convention: .borrowed, type: .scalar(scalar))]
        case .conversion(let scalar, _):
            [FunctionParameter(label: nil, convention: .owned, type: .scalar(scalar))]
        }
    }

    public var result: RayoType {
        switch self {
        case .print: .void
        case .conversion(_, let target): .scalar(target)
        }
    }
}
