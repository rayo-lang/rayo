/// The statement that drops the value of a place that no code uses, as an error names it: `'_ = n'` or
/// `'_ = consume item'`.
public struct DropStatement: Sendable, Hashable, CustomStringConvertible {
    /// What the statement writes before the place.
    public var mark: DropMark
    /// The place as the source writes it, such as `n` or `item`.
    public var place: String

    public init(_ mark: DropMark, dropping place: String) {
        self.mark = mark
        self.place = place
    }

    public var description: String { "'\(mark.spelling) \(place)'" }
}
