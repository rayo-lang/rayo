/// A struct's field as a function body sees it, which a call of the struct's initializer gives and a read names.
struct DeclaredField {
    var name: String
    /// The type, or nil where the field's declaration failed, which was reported there.
    var type: RayoType?
}
