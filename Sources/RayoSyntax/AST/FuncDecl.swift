import RayoSource

/// `func name(parameters) -> Result { … }`, where the result type is optional.
public struct FuncDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    public var parameters: [Param]
    public var result: TypeExpr?
    public var body: Block
}
