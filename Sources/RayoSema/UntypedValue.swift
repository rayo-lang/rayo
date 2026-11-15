import RayoDiagnostics
import RayoSource

/// A value with no type of its own until one settles it: an integer literal, or a negation or arithmetic on untyped
/// values.
indirect enum UntypedValue {
    /// An integer literal, by its digits' value and whether a `-` written onto it negates it.
    case integer(magnitude: UInt64, isNegative: Bool, range: SourceRange)
    /// `-operand`.
    case negation(UntypedValue, range: SourceRange)
    /// `left op right`, where `op` gives a value of its operands' type.
    case arithmetic(CheckedBinaryOperator, UntypedValue, UntypedValue, range: SourceRange)

    var range: SourceRange {
        switch self {
        case .integer(_, _, let range), .negation(_, let range), .arithmetic(_, _, _, let range): range
        }
    }

    /// The type the value settles to where nothing else gives it one.
    private static let integerDefault = RayoType.int

    /// Settles the value to `type`, which it fits, reporting each literal whose value `type` can't hold. An error
    /// names `type` as `typeName`.
    func settled(to type: RayoType, named typeName: TypeName, reporting errors: ErrorList) -> CheckedExpr? {
        switch self {
        // A literal keeps its value, if the type holds it.
        case .integer(let magnitude, let isNegative, let range):
            Self.literal(magnitude, isNegative: isNegative, as: type, named: typeName, at: range, reporting: errors)

        // A negation's operand settles to the negation's type.
        case .negation(let operand, let range):
            operand.settled(to: type, named: typeName, reporting: errors).map {
                CheckedExpr(kind: .unary(.negate, $0), type: type, range: range)
            }

        // Both operands settle to the operator's type.
        case .arithmetic(let op, let left, let right, let range):
            Self.arithmetic(op, left, right, as: type, named: typeName, at: range, reporting: errors)
        }
    }

    /// Settles the integer literal of `magnitude`, negated where `isNegative`, which the source gives at `range`, to
    /// `type`, reporting it where `type` can't hold its value.
    private static func literal(_ magnitude: UInt64, isNegative: Bool, as type: RayoType, named typeName: TypeName,
                                at range: SourceRange, reporting errors: ErrorList) -> CheckedExpr? {
        // Only an integer type takes an integer literal, which fits where its value is among the type's values.
        guard case .scalar(let scalar) = type, let values = scalar.literalRange else {
            preconditionFailure("an integer literal settles only to an integer type")
        }
        let value = isNegative ? -Int128(magnitude) : Int128(magnitude)

        // A literal the type can't hold is reported.
        guard values.contains(value) else {
            errors.report(.literalDoesntFit(type: typeName), at: range)
            return nil
        }
        return CheckedExpr(kind: .integerLiteral(value, scalar), type: type, range: range)
    }

    /// Settles `left op right`, which the source gives at `range`, to `type`, settling both operands to it.
    private static func arithmetic(
        _ op: CheckedBinaryOperator, _ left: UntypedValue, _ right: UntypedValue, as type: RayoType,
        named typeName: TypeName, at range: SourceRange, reporting errors: ErrorList,
    ) -> CheckedExpr? {
        // Both operands settle, so each one's errors are reported.
        let left = left.settled(to: type, named: typeName, reporting: errors)
        let right = right.settled(to: type, named: typeName, reporting: errors)
        // An operand that failed was reported.
        guard let left, let right else { return nil }
        return CheckedExpr(kind: .binary(op, left, right), type: type, range: range)
    }
}

extension UntypedValue: WaitingValue {
    /// None: the value has no type until its position gives one.
    var type: RayoType? { nil }

    var defaultType: RayoType? { Self.integerDefault }

    /// Whether the value can settle to `type`. An integer literal fits every integer type, and nothing else.
    func fits(_ type: RayoType, in _: Declarations) -> Bool {
        type.isInteger
    }

    /// Settles the value to `type` where it fits it, and to its default type where it doesn't or `type` is nil.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        let settledType = if let type, fits(type, in: expressions.file.declarations) {
            type
        } else {
            Self.integerDefault
        }
        let typeName = expressions.typeName(of: settledType)
        return settled(to: settledType, named: typeName, reporting: expressions.file.errors)
    }
}
