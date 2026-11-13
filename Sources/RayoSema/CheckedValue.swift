import RayoDiagnostics
import RayoSource
import RayoSyntax

/// What checking an expression gives before its position is known: a typed value, or an untyped one that waits for a
/// type to settle it.
enum CheckedValue {
    case typed(CheckedExpr)
    case untyped(UntypedValue)

    /// The value's type, or nil where it is untyped.
    var type: RayoType? {
        switch self {
        case .typed(let value): value.type
        case .untyped: nil
        }
    }

    /// Whether a parameter of `type` takes the value: a typed value of that type, or an untyped one that fits it.
    func fits(_ type: RayoType) -> Bool {
        switch self {
        case .typed(let value): value.type == type
        case .untyped(let value): value.fits(type)
        }
    }
}

/// A value with no type of its own until one settles it: an integer literal, or a negation or arithmetic on untyped
/// values.
indirect enum UntypedValue {
    /// An integer literal, by its digits' value and whether a `-` written onto it negates it.
    case integer(magnitude: UInt64, isNegative: Bool, range: SourceRange)
    /// `-operand`.
    case negation(UntypedValue, range: SourceRange)
    /// `left op right`, where `op` gives a value of its operands' type.
    case arithmetic(BinaryOperator, UntypedValue, UntypedValue, range: SourceRange)

    var range: SourceRange {
        switch self {
        case .integer(_, _, let range), .negation(_, let range), .arithmetic(_, _, _, let range): range
        }
    }

    /// The type the value settles to where nothing else gives it one.
    var defaultType: RayoType { .int }

    /// Whether the value can settle to `type`. An integer literal fits every integer type, and nothing else.
    func fits(_ type: RayoType) -> Bool {
        switch type {
        case .int: true
        case .bool, .void, .structure: false
        }
    }

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
        // Find the literal's value among the type's values.
        let value: Int64? = switch type {
        case .int: int(magnitude, isNegative: isNegative)
        case .bool, .void, .structure: preconditionFailure("an integer literal settles only to an integer type")
        }

        // A literal the type can't hold is reported.
        guard let value else {
            errors.report(.literalExceedsInt(type: typeName), at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: type, range: range)
    }

    /// Settles `left op right`, which the source gives at `range`, to `type`, settling both operands to it.
    private static func arithmetic(
        _ op: BinaryOperator, _ left: UntypedValue, _ right: UntypedValue, as type: RayoType, named typeName: TypeName,
        at range: SourceRange, reporting errors: ErrorList,
    ) -> CheckedExpr? {
        // Both operands settle, so each one's errors are reported.
        let left = left.settled(to: type, named: typeName, reporting: errors)
        let right = right.settled(to: type, named: typeName, reporting: errors)
        // An operand that failed was reported.
        guard let left, let right else { return nil }
        return CheckedExpr(kind: .binary(op, left, right), type: type, range: range)
    }

    /// The Int that a literal of `magnitude`, negated where `isNegative`, has, or nil where no Int holds it.
    private static func int(_ magnitude: UInt64, isNegative: Bool) -> Int64? {
        // A positive literal fits where its digits do.
        guard isNegative else { return Int64(exactly: magnitude) }
        // A negative literal fits one value more than a positive one: `Int.min`, whose magnitude no Int holds.
        return magnitude == Int64.min.magnitude ? Int64.min : Int64(exactly: magnitude).map { -$0 }
    }
}
