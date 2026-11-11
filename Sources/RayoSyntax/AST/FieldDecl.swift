import RayoSource

/// `var name: Type` or `let name: Type` in a struct's header, where the type is optional.
public struct FieldDecl: Sendable {
    public var kind: BindingKind
    public var name: String
    public var nameRange: SourceRange
    public var type: TypeExpr?
}
