internal import RayoSource

/// Thrown by the parser once it has reported the syntax errors of a declaration that failed, with what it read of the
/// declaration.
struct DeclarationFailure: Error {
    /// What the parser read of the declaration its keyword began, or nil where no keyword began one.
    var parts: FailedDeclParts?
    /// The declaration's name, or nil where it failed before its name.
    var name: String?
    /// Where the name is written, or nil where the declaration failed before its name.
    var nameRange: SourceRange?
}
