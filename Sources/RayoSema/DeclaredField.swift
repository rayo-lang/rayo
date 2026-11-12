/// A struct's field as a function body sees it.
struct DeclaredField {
    var name: String
    /// The type, or nil where the field's declaration failed, which was reported there.
    var type: RayoType?
}
