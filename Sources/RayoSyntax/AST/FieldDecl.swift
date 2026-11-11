public import RayoSource

/// `var name: Type = value` or `let name: Type = value` in a struct's header, where the type and the default value
/// are each optional.
public struct FieldDecl: Sendable {
    public var kind: BindingKind
    public var name: String
    public var nameRange: SourceRange
    public var type: TypeExpr?
    public var defaultValue: Expr?
}
