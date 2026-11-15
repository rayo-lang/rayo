import RayoSema
import RayoSource

public enum IRLocal: Equatable, Sendable {
    /// A local or a parameter that the source declares, with the name and the kind it declares it with, and where it
    /// declares the name.
    case source(name: String, kind: LocalKind, type: RayoType, range: SourceRange)
    /// A temporary that lowering adds to hold a value it computes.
    case temporary(RayoType)

    public var type: RayoType {
        switch self {
        case .source(_, _, let type, _), .temporary(let type): type
        }
    }

    /// The convention of the parameter the local is, or nil where it is no parameter.
    public var parameterConvention: ParameterConvention? {
        guard case .source(_, .parameter(let convention), _, _) = self else { return nil }
        return convention
    }
}
