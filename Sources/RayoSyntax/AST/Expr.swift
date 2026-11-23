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
    /// `callee(arguments)`, where the callee is a name, a member or an implicit member.
    case call(callee: Expr, arguments: [Argument])
    /// `value.name`: the member `name` of the value.
    case member(Expr, name: String, nameRange: SourceRange)
    /// `.name`: the member `name` of the type its position expects.
    case implicitMember(name: String)
    case unary(UnaryOperator, Expr)
    case binary(BinaryOperator, Expr, Expr)
    /// `value[index]`: the element at `index` of the array `value`.
    case element(Expr, index: Expr)
    /// `copy place`: the value of a local, or of a part of one at any depth, which the place keeps. `place` is a
    /// name, a member of a place, or an element of one.
    case copy(Expr)
    /// `consume place`: the value moved out of a local, or out of a part of one at any depth, which then holds no
    /// value until it is assigned again. `place` is a name, a member of a place, or an element of one.
    case consume(Expr)
    /// `&place`: a shared reference to a local, or to a part of one at any depth, which borrows the place. `place` is
    /// a name, a member of a place, or an element of one.
    case reference(Expr)
    /// `mutable &place`: a mutable reference to a local, or to a part of one at any depth, which borrows the place
    /// for change. `place` is a name, a member of a place, or an element of one.
    case mutableReference(Expr)
    /// An `if` whose value is that of the branch that runs.
    case `if`(IfExpr)
    /// `[elements]`: an array literal, whose elements are in the order the source writes them.
    case arrayLiteral([Expr])
}

/// `label: value`, or the value alone.
public struct Argument: Sendable {
    public var label: String?
    public var value: Expr
    /// The label, when there is one, and the value.
    public var range: SourceRange
}
