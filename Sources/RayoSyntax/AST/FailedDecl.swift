public import RayoSource

/// A top-level declaration that failed to parse, whose syntax error was reported, with what the parser read of it.
public struct FailedDecl: Sendable {
    /// The kind of declaration its keyword began.
    public enum Kind: Sendable {
        case function
        case structure
    }

    public var kind: Kind
    /// The declaration's name, or nil where it failed before its name.
    public var name: String?
    /// The source the declaration covers, up to where the parser stopped skipping it.
    public var range: SourceRange
}
