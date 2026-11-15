/// A part that a statement or an expression holds directly: an expression, or a block of statements.
public enum SyntaxChild: Sendable {
    case expression(Expr)
    case block(Block)
}
