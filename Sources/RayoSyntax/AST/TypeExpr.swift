import RayoSource

public enum TypeExpr: Sendable {
    /// `Int`.
    case named(String, range: SourceRange)
    /// `()`.
    case void(range: SourceRange)

    public var range: SourceRange {
        switch self {
        case .named(_, let range), .void(let range): return range
        }
    }

    /// The type as the source writes it.
    public var spelling: String {
        switch self {
        case .named(let name, _): return name
        case .void: return "()"
        }
    }
}
