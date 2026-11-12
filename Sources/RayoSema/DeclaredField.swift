import RayoSyntax

/// A struct's field as a function body sees it.
struct DeclaredField {
    var name: String
    /// Whether the field is a `var`, which an assignment may change, or a `let`, which it can't.
    var kind: BindingKind
    /// The type, or nil where the field's declaration failed, which was reported there.
    var type: RayoType?
}
