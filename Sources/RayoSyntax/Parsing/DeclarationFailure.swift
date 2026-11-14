internal import RayoSource

/// Thrown by the parser once it has reported the syntax error that ended a top-level declaration, with what it read
/// of the declaration before it.
struct DeclarationFailure: Error {
    /// The kind of declaration the keyword began, or nil where no keyword began one.
    var kind: FailedDecl.Kind?
    /// The declaration's name, or nil where it failed before its name.
    var name: String?
    /// Where the name is written, or nil where the declaration failed before its name.
    var nameRange: SourceRange?
}
