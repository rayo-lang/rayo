/// What the parser read of a declaration that failed, by the kind of declaration its keyword began.
public enum FailedDeclParts: Sendable {
    /// A function's parameters, its result type and its body, each nil where the parser found none or it failed.
    case function(parameters: [HeaderItem<Param>], result: TypeExpr?, body: Block?)
    /// A struct's fields, and the declarations in its body, none where its body failed.
    case structure(fields: [HeaderItem<FieldDecl>], members: [Declaration])
}
