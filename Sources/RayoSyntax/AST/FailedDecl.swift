public import RayoSource

/// A declaration that failed to parse, whose syntax errors were reported, with what the parser read of it.
public struct FailedDecl: Sendable {
    /// The declaration's name, or nil where it failed before its name.
    public var name: String?
    /// Where the name is written, or nil where the declaration failed before its name.
    public var nameRange: SourceRange?
    /// What the parser read of the declaration's header and body, which also says its kind.
    public var parts: FailedDeclParts
    /// The source the declaration covers, up to where the parser stopped skipping it.
    public var range: SourceRange
}
