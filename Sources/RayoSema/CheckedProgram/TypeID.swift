/// Identifies one of a program's named types by the kind of declaration that declares it, and carries the name the
/// program declares it by.
public enum TypeID: Hashable, Sendable {
    case structure(StructID)

    public var name: String {
        switch self {
        case .structure(let id): id.name
        }
    }
}
