import RayoSource
import RayoSyntax

/// A file's declaration of a type, by its kind.
enum TypeDeclaration {
    case structure(StructDecl)
    /// A type declaration that failed to parse after its name, `name`. `range` covers the whole declaration, which
    /// stands in for where its name is written.
    case failed(name: String, range: SourceRange)

    /// The type declarations of `file`, of every kind, in source order, those that failed to parse with a name among
    /// them.
    static func all(in file: SourceFile) -> [TypeDeclaration] {
        let failed = file.failedDeclarations.compactMap { declaration -> TypeDeclaration? in
            guard declaration.kind == .structure, let name = declaration.name else { return nil }
            return .failed(name: name, range: declaration.range)
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
        case .failed(_, let range): range
        }
    }
}
