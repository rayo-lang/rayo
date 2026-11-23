public import RayoSource

/// A declaration that failed to parse, whose syntax errors were reported, with what the parser read of it.
public struct FailedDecl: Sendable {
    /// The kind of declaration its keyword began.
    public enum Kind: Sendable {
        case function
        case structure
    }

    /// What the parser read of a declaration's header and body, by its kind.
    public enum Parts: Sendable {
        /// A function's parameters and result type, and its body, nil where the parser found none or the body failed.
        case function(parameters: [HeaderItem<Param>], result: TypeExpr?, body: Block?)
        /// A struct's fields, and the declarations in its body, none where its body failed.
        case structure(fields: [HeaderItem<FieldDecl>], members: [Declaration])
    }

    /// A parameter or a field in a declaration's header: one that parsed, or one that failed, whose syntax error was
    /// reported.
    public enum HeaderItem<Item: Sendable>: Sendable {
        case parsed(Item)
        case failed
    }

    /// The declaration's name, or nil where it failed before its name.
    public var name: String?
    /// Where the name is written, or nil where the declaration failed before its name.
    public var nameRange: SourceRange?
    public var parts: Parts
    /// The source the declaration covers, up to where the parser stopped skipping it.
    public var range: SourceRange

    public var kind: Kind {
        switch parts {
        case .function: .function
        case .structure: .structure
        }
    }
}
