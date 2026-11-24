import RayoCheckedProgram
import RayoSyntax

extension DeclarationKind {
    /// The position of the declaration's value.
    var valuePosition: Position {
        switch self {
        case .let, .var: .ownerDeclaration(keyword: keyword)
        case .refLet: .referenceDeclaration
        case .refVar: .mutableReferenceDeclaration
        }
    }
}
