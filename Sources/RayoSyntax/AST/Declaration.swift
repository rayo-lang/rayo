public import RayoSource

/// A declaration at a file's top level or in a type's body: a function, a struct, or one that failed to parse.
public enum Declaration: Sendable {
    case function(FuncDecl)
    case structure(StructDecl)
    case failed(FailedDecl)

    /// The name the declaration declares, or nil where it failed before its name.
    public var name: String? {
        switch self {
        case .function(let function): function.name
        case .structure(let structure): structure.name
        case .failed(let failed): failed.name
        }
    }

    /// Where the name is written, or nil where the declaration failed before its name.
    public var nameRange: SourceRange? {
        switch self {
        case .function(let function): function.nameRange
        case .structure(let structure): structure.nameRange
        case .failed(let failed): failed.nameRange
        }
    }

    /// Whether the declaration declares a type rather than a function, which its keyword tells even where it failed.
    public var declaresType: Bool {
        switch self {
        case .function: false
        case .structure: true
        case .failed(let failed):
            switch failed.parts {
            case .function: false
            case .structure: true
            }
        }
    }
}
