/// The label an argument is written with, as an error names it: `'by:'`, or `no label`.
public enum ArgumentLabel: Sendable, Hashable, CustomStringConvertible {
    case label(String)
    case none

    public init(_ label: String?) {
        self = label.map { .label($0) } ?? .none
    }

    public var description: String {
        switch self {
        case .label(let label): return "'\(label):'"
        case .none: return "no label"
        }
    }
}
