public import RayoSource

public indirect enum TypeExpr: Sendable {
    /// `Int`.
    case named(String, range: SourceRange)
    /// `()`.
    case void(range: SourceRange)
    /// `[count of element]`: an array of `count` values of the element's type, where the count is an integer
    /// literal's digits.
    case array(count: UInt64, element: TypeExpr, range: SourceRange)

    public var range: SourceRange {
        switch self {
        case .named(_, let range), .void(let range), .array(_, _, let range): return range
        }
    }

    /// The type as the source writes it.
    public var spelling: String {
        switch self {
        case .named(let name, _): return name
        case .void: return "()"
        case .array(let count, let element, _): return "[\(count) of \(element.spelling)]"
        }
    }
}
