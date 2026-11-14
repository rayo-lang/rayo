/// A type the file declares, by the kind of declaration that declares it.
enum DeclaredType {
    case structure(StructID)
    /// A type whose declaration failed to parse, and which names no type.
    case failed(name: String)

    var name: String {
        switch self {
        case .structure(let id): id.name
        case .failed(let name): name
        }
    }

    /// The type that a use of the declaration's name names, or nil where the declaration failed to parse.
    var type: RayoType? {
        switch self {
        case .structure(let id): .structure(id)
        case .failed: nil
        }
    }
}
