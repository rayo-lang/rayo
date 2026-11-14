import RayoSource
import RayoSyntax

/// A file's declaration of a type, by its kind.
enum TypeDeclaration {
    case structure(StructDecl)

    /// The type declarations of `file`, of every kind, in source order.
    static func all(in file: SourceFile) -> [TypeDeclaration] {
        file.structs.map(TypeDeclaration.structure).sorted { $0.nameRange.start < $1.nameRange.start }
    }

    var name: String {
        switch self {
        case .structure(let declaration): declaration.name
        }
    }

    var nameRange: SourceRange {
        switch self {
        case .structure(let declaration): declaration.nameRange
        }
    }
}
