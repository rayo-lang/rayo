import RayoDiagnostics
import RayoSource

/// What checking an expression gives before its position is known: a typed value, or an untyped one, an array
/// literal or an implicit member, each of which waits for a type to settle it.
enum CheckedValue {
    case typed(CheckedExpr)
    case untyped(UntypedValue)
    /// An array literal, whose type, and so its elements' types, its position gives where it gives one.
    case arrayLiteral(ArrayLiteral)
    /// An implicit member, such as `.init(all: 0)`, which names a member of the type its position gives.
    case implicitMember(ImplicitMember)

    /// The value's type, or nil where its position settles it.
    var type: RayoType? {
        switch self {
        case .typed(let value): value.type
        case .untyped, .arrayLiteral, .implicitMember: nil
        }
    }

    /// The value's type, or the type it settles to where its position gives none: an untyped value's default, and
    /// an array literal's from its elements. Nil for a literal no element gives a type, such as `[]`, and for an
    /// implicit member, which names a member of no type until its position gives one.
    var typeOrDefault: RayoType? {
        switch self {
        case .typed(let value): value.type
        case .untyped(let value): value.defaultType
        case .arrayLiteral(let literal):
            literal.defaultElementType.map { .array(count: literal.elements.count, element: $0) }
        case .implicitMember: nil
        }
    }

    /// Whether a parameter of `type` takes the value: a typed value of that type, an untyped one that fits it, an
    /// array literal of the type's count whose elements each fit the type's element type, or an implicit member that
    /// makes a value of the type.
    func fits(_ type: RayoType) -> Bool {
        switch self {
        case .typed(let value): value.type == type
        case .untyped(let value): value.fits(type)
        case .arrayLiteral(let literal): literal.fits(type)
        case .implicitMember(let member): member.fits(type)
        }
    }
}

/// An array literal's elements, each checked on its own, and where the source writes the literal.
struct ArrayLiteral {
    var elements: [CheckedValue]
    var range: SourceRange

    /// The type the elements settle to where the literal's position gives none: the type of the first typed element,
    /// or, where none is typed, the first default type among them. Nil where no element gives one.
    var defaultElementType: RayoType? {
        elements.lazy.compactMap(\.type).first ?? elements.lazy.compactMap(\.typeOrDefault).first
    }

    /// Whether the literal can settle to `type`: an array of as many elements as the literal, each of which fits
    /// its element type.
    func fits(_ type: RayoType) -> Bool {
        guard case .array(let count, let element) = type, count == elements.count else { return false }
        return elements.allSatisfy { $0.fits(element) }
    }
}

/// An implicit member, such as `.init(all: 0)`: its name, and the arguments of the call where it is called, each
/// checked on its own.
struct ImplicitMember {
    /// An argument of the call: its label, its value checked on its own, and where the source writes both.
    struct Argument {
        var label: String?
        var value: CheckedValue
        var range: SourceRange
    }

    var name: String
    /// Where the source writes the `.` and the name.
    var nameRange: SourceRange
    /// The call's arguments, or nil where the member isn't called.
    var arguments: [Argument]?
    /// Where the source writes the member, with the call's arguments where it is called.
    var range: SourceRange

    /// The values of the call's arguments; none where the member isn't called.
    var argumentValues: [CheckedValue] {
        arguments?.map(\.value) ?? []
    }

    /// The value that `.init(all: value)`, the one member an array has, fills it with; nil for any other member. An
    /// array's members are told apart here alone, so checking a member and picking among overloads agree.
    var fillingValue: CheckedValue? {
        guard name == "init", let arguments, arguments.count == 1, arguments[0].label == "all" else { return nil }
        return arguments[0].value
    }

    /// Whether the member makes a value of `type`: an array, filled with a value that fits its element type.
    func fits(_ type: RayoType) -> Bool {
        guard case .array(_, let element) = type, let fillingValue else { return false }
        return fillingValue.fits(element)
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
    case arithmetic(CheckedBinaryOperator, UntypedValue, UntypedValue, range: SourceRange)

    var range: SourceRange {
        switch self {
        case .integer(_, _, let range), .negation(_, let range), .arithmetic(_, _, _, let range): range
        }
    }

    /// The type the value settles to where nothing else gives it one.
    var defaultType: RayoType { .int }

    /// Whether the value can settle to `type`. An integer literal fits every integer type, and nothing else.
    func fits(_ type: RayoType) -> Bool {
        type.isInteger
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
        let kind: CheckedExprKind? = switch type {
        case .int: int(magnitude, isNegative: isNegative).map(CheckedExprKind.intLiteral)
        case .uint: uint(magnitude, isNegative: isNegative).map(CheckedExprKind.uintLiteral)
        case .bool, .void, .structure, .array:
            preconditionFailure("an integer literal settles only to an integer type")
        }

        // A literal the type can't hold is reported.
        guard let kind else {
            errors.report(.literalDoesntFit(type: typeName), at: range)
            return nil
        }
        return CheckedExpr(kind: kind, type: type, range: range)
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

    /// The Int that a literal of `magnitude`, negated where `isNegative`, has, or nil where no Int holds it.
    private static func int(_ magnitude: UInt64, isNegative: Bool) -> Int64? {
        // A positive literal fits where its digits do.
        guard isNegative else { return Int64(exactly: magnitude) }
        // A negative literal fits one value more than a positive one: `Int.min`, whose magnitude no Int holds.
        return magnitude == Int64.min.magnitude ? Int64.min : Int64(exactly: magnitude).map { -$0 }
    }

    /// The UInt that a literal of `magnitude`, negated where `isNegative`, has, or nil where no UInt holds it.
    private static func uint(_ magnitude: UInt64, isNegative: Bool) -> UInt64? {
        // Every positive literal fits, since its digits fit in 64 bits, and of the negative ones only `-0` does.
        isNegative && magnitude != 0 ? nil : magnitude
    }
}
