/// What the parser found where it expected something else.
public enum FoundToken: Sendable, Hashable, CustomStringConvertible {
    /// A token, as the source spells it.
    case token(String)
    case newline
    case endOfFile

    public var description: String {
        switch self {
        case .token(let spelling): return "'\(spelling)'"
        case .newline: return "a newline"
        case .endOfFile: return "the end of the file"
        }
    }
}
