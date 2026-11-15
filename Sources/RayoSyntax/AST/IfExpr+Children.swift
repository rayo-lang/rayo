extension IfExpr {
    /// The condition, then the block that runs where it holds, then the `else` block where there is one.
    public var children: [SyntaxChild] {
        [.expression(condition), .block(then)] + (otherwise.map { [.block($0)] } ?? [])
    }
}
