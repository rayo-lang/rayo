import RayoSyntax

extension DeclarationKind {
    /// The words that start the declaration, as an error names them.
    var keyword: String {
        switch self {
        case .let: "let"
        case .var: "var"
        case .refLet: "ref let"
        case .refVar: "ref var"
        }
    }
}
