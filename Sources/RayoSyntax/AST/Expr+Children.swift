extension Expr {
    /// The expressions and blocks the expression holds directly, in source order.
    /// A traversal that follows where a run goes, such as the checker's reachability, names each form that changes
    /// it, and walks every other form's children.
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
