import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

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

    /// `-self`, which the source gives at `range`. A `-` written onto a literal, as in `-(1)`, makes one literal of
    /// the opposite sign, so the literal's own range check decides whether a type holds it.
    func negated(at range: SourceRange) -> UntypedValue {
        if case .integer(let magnitude, let isNegative, _) = self {
            .integer(magnitude: magnitude, isNegative: !isNegative, range: range)
        } else {
            .negation(self, range: range)
        }
    }

    /// The type the value settles to where nothing else gives it one.
    private static let integerDefault = ScalarType.int

    /// Whether `values`, those an integer type holds, include the value of each literal in the value.
    private func holdsLiterals(_ values: ClosedRange<Int128>) -> Bool {
        switch self {
        case .integer(let magnitude, let isNegative, _): values.contains(Self.value(magnitude, isNegative: isNegative))
        case .negation(let operand, _): operand.holdsLiterals(values)
        case .arithmetic(_, let left, let right, _): left.holdsLiterals(values) && right.holdsLiterals(values)
        }
    }

    /// The value of the integer literal of `magnitude`, negated where `isNegative`.
    private static func value(_ magnitude: UInt64, isNegative: Bool) -> Int128 {
        isNegative ? -Int128(magnitude) : Int128(magnitude)
    }

    /// Settles the value to `type`, which it fits, reporting each literal whose value `type` can't hold. An error
    /// names `type` as `typeName`.
    func settled(to type: RayoType, named typeName: TypeName, reporting errors: ErrorList) -> CheckedExpr? {
        switch self {
        // A literal keeps its value, if the type holds it.
        case .integer(let magnitude, let isNegative, let range):
            Self.literal(magnitude, isNegative: isNegative, as: type, named: typeName, at: range, reporting: errors)

        // A negation's operand settles to the negation's type, which must be signed.
        case .negation(let operand, let range):
            Self.negation(operand, as: type, named: typeName, at: range, reporting: errors)

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
        let literalValue = value(magnitude, isNegative: isNegative)

        // A literal the type can't hold is reported. It keeps the value it writes, so lowering and the ownership checks
        // still pass over the body. The value is never emitted, since the error ends the compile before emitting.
        if !values.contains(literalValue) {
            errors.reportKeepingMeaning(.literalDoesntFit(type: typeName), at: range)
        }
        return CheckedExpr(kind: .integerLiteral(literalValue, scalar), type: type, range: range)
    }

    /// Settles `-operand`, which the source gives at `range`, to `type`, reporting it where `type` has no sign.
    private static func negation(_ operand: UntypedValue, as type: RayoType, named typeName: TypeName,
                                 at range: SourceRange, reporting errors: ErrorList) -> CheckedExpr? {
        // Negating an unsigned value overflows for every value but 0, so only a signed type has `-`. The operand
        // isn't settled then, since a negation inside it would report the same mistake again.
        guard type.isSigned else {
            errors.report(.signedOperand(op: UnaryOperator.negate.rawValue, found: typeName), at: range)
            return nil
        }
        return operand.settled(to: type, named: typeName, reporting: errors).map {
            CheckedExpr(kind: .unary(.negate, $0), type: type, range: range)
        }
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

    var defaultType: RayoType? { .scalar(Self.integerDefault) }

    /// Whether `type` is an integer type that takes the value as written, with no arithmetic worked out.
    func fits(_ type: RayoType, in _: Declarations) -> Bool {
        guard case .scalar(let scalar) = type, let values = scalar.literalRange else { return false }
        return switch self {
        // A literal fits where its value is among the type's.
        case .integer(let magnitude, let isNegative, _): values.contains(Self.value(magnitude, isNegative: isNegative))
        // Only a signed type has `-`.
        case .negation: scalar.isSigned
        // Arithmetic fits every integer type, whatever its operands hold.
        case .arithmetic: true
        }
    }

    /// Whether `type` is an integer type, the only kind the value settles to.
    func canSettle(to type: RayoType, in _: Declarations) -> Bool {
        type.isInteger
    }

    /// Settles the value to `type` where it fits it, and to its default type where it doesn't or `type` is nil.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        let errors = expressions.file.errors
        let defaultType = RayoType.scalar(Self.integerDefault)

        // A position that expects an integer type settles the value to it, and one that gives no type settles it to
        // the default. A literal that type can't hold is reported, and keeps its value, since the value has that type.
        guard let type, !canSettle(to: type, in: expressions.file.declarations) else {
            let settledType = type ?? defaultType
            return settled(to: settledType, named: expressions.typeName(of: settledType), reporting: errors)
        }

        // A position whose type takes no integer settles the value to the default, and reports it as a mismatch. A
        // literal the default can't hold is reported instead, as the only error. The value then fails, and the body
        // is tainted, since no checked value stands for it.
        let defaulted = settled(to: defaultType, named: expressions.typeName(of: defaultType), reporting: errors)
        guard let values = Self.integerDefault.literalRange, holdsLiterals(values) else {
            errors.taints.taint()
            return nil
        }
        return defaulted
    }
}
