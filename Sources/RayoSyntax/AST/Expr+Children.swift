extension Expr {
    /// The expressions and blocks the expression holds directly, in source order.
    public var children: [SyntaxChild] {
        switch kind {
        case .intLiteral, .negativeIntLiteral, .boolLiteral, .name, .implicitMember: []
        case .member(let base, _, _), .copy(let base), .unary(_, let base): [.expression(base)]
        case .binary(_, let left, let right): [.expression(left), .expression(right)]
        case .element(let base, let index): [.expression(base), .expression(index)]
        case .call(let callee, let arguments): [.expression(callee)] + arguments.map { .expression($0.value) }
        case .arrayLiteral(let elements): elements.map(SyntaxChild.expression)
        case .if(let ifExpr): ifExpr.children
        }
    }
}
