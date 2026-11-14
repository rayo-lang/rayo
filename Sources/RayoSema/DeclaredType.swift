/// A type the file declares, by the kind of declaration that declares it.
enum DeclaredType {
    case structure(StructID)

    var name: String {
        switch self {
        case .structure(let id): id.name
        }
    }

    /// The type that a use of the declaration's name names.
    var type: RayoType {
        switch self {
        case .structure(let id): .structure(id)
        }
    }
}
