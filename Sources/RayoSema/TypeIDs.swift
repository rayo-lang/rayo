/// The IDs that declaring a file's type names gave its types, one list for each kind of type declaration, in the
/// order the file declares that kind.
struct TypeIDs {
    /// The ID of each struct, nil for each whose name is `_` or another type's.
    var structs: [StructID?]
}
