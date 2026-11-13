public import RayoSource

public struct Block: Sendable {
    public var statements: [Stmt]
    /// The `}` that ends the block.
    public var closingBrace: SourceRange

    /// The block's one statement, when it is an expression.
    public var singleExpression: Expr? {
        // A block of no statements, of several, or of one that isn't an expression, has none.
        guard statements.count == 1, case .expression(let expr) = statements[0].kind else { return nil }
        return expr
    }

    /// The block's last statement as an expression, when it is an expression or an `if`.
    public var lastExpression: Expr? {
        switch statements.last?.kind {
        // An expression statement holds the expression itself.
        case .expression(let expr): expr
        // An `if` that starts the statement is the same `if` as an expression, over the statement's range.
        case .ifStmt(let ifExpr): Expr(kind: .if(ifExpr), range: statements[statements.count - 1].range)
        // An empty block has no last expression, and nor does one whose last statement is any other.
        default: nil
        }
    }
}
