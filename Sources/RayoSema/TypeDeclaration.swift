import RayoSource
import RayoSyntax

/// A file's declaration of a type, by its kind.
enum TypeDeclaration {
    case structure(StructDecl)
    /// A type declaration that failed to parse after its name, `name`, which is written at `nameRange`.
    case failed(name: String, nameRange: SourceRange)

    /// The type declarations of `file`, of every kind, in source order, those that failed to parse with a name among
    /// them.
    static func all(in file: SourceFile) -> [TypeDeclaration] {
        let failed = file.failedDeclarations.compactMap { declaration -> TypeDeclaration? in
            guard declaration.kind == .structure, let name = declaration.name, let nameRange = declaration.nameRange
            else { return nil }
            return .failed(name: name, nameRange: nameRange)
        }
        let declarations = file.structs.map(TypeDeclaration.structure) + failed
        return declarations.sorted { $0.nameRange.start < $1.nameRange.start }
    }

    var name: String {
        switch self {
        case .structure(let declaration): declaration.name
        case .failed(let name, _): name
        }
    }

    var nameRange: SourceRange {
        switch self {
        case .structure(let declaration): declaration.nameRange
        case .failed(_, let nameRange): nameRange
        }
    }
}
