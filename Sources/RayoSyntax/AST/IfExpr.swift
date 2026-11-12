/// `if condition { … } else { … }`, where the `else` part is optional. An `else if` is an `else` block whose one
/// statement is the nested `if`.
public struct IfExpr: Sendable {
    public var condition: Expr
    public var then: Block
    public var otherwise: Block?
}
