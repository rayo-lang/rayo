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
}
