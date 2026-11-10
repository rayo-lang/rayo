import RayoSema

public enum IRLocal: Equatable, Sendable {
    /// A local or a parameter that the source declares, with the name and the kind it declares it with.
    case source(name: String, kind: LocalKind, type: RayoType)
    /// A temporary that lowering adds to hold a value it computes.
    case temporary(RayoType)

    public var type: RayoType {
        switch self {
        case .source(_, _, let type), .temporary(let type): return type
        }
    }
}
