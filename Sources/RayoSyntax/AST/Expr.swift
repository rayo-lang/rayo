public import RayoSource

public struct Expr: Sendable {
    public var kind: ExprKind
    public var range: SourceRange
}

public indirect enum ExprKind: Sendable {
    /// The literal's digits.
    case intLiteral(UInt64)
    /// `-digits`: a `-` with no operator between it and a literal, which is one literal with the negated
    /// value, so that `-9223372036854775808` is `Int.min` though `9223372036854775808` doesn't fit in an `Int`.
    case negativeIntLiteral(UInt64)
    case boolLiteral(Bool)
    case name(String)
    /// `name(arguments)`.
    case call(name: String, nameRange: SourceRange, arguments: [Argument])
    /// `value.name`: the member `name` of the value.
    case member(Expr, name: String, nameRange: SourceRange)
    case unary(UnaryOperator, Expr)
    case binary(BinaryOperator, Expr, Expr)
    /// `copy place`: the value of a local, or of a field of one at any depth, which the place keeps. `place` is a
    /// name, or a member of a place.
    case copy(Expr)
}

/// `label: value`, or the value alone.
public struct Argument: Sendable {
    public var label: String?
    public var value: Expr
    /// The label, when there is one, and the value.
    public var range: SourceRange
}
