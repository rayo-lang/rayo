extension Stmt {
    /// The expressions and blocks the statement holds directly, in source order.
    public var children: [SyntaxChild] {
        switch kind {
        case .declaration(_, let bindings): bindings.compactMap { $0.value.map(SyntaxChild.expression) }
        case .assign(let target, _, let value): [.expression(target), .expression(value)]
        case .drop(let value), .expression(let value), .returnStmt(let value?): [.expression(value)]
        case .ifStmt(let ifExpr): ifExpr.children
        case .whileStmt(let condition, let body): [.expression(condition), .block(body)]
        case .breakStmt, .continueStmt, .returnStmt(nil), .error: []
        }
    }
}
