/// What a statement writes before a value that no code uses, to drop it, as an error names it: `'_ ='`,
/// `'_ = consume'` or `'_ = copy'`.
public enum DropMark: Sendable, Hashable, CustomStringConvertible {
    /// `_ =` before the value bare, which drops a value that no place holds, or a copy of a place's implicitly
    /// copyable value.
    case bare
    /// `_ = consume`, which moves the value out of a place and drops it.
    case consume
    /// `_ = copy`, which drops a copy of a place's value, where the code can't move the value out of the place.
    case copy

    public var description: String { "'\(spelling)'" }

    /// The mark as the source writes it, without the quotes an error puts around it.
    var spelling: String {
        switch self {
        case .bare: "_ ="
        case .consume: "_ = consume"
        case .copy: "_ = copy"
        }
    }
}
