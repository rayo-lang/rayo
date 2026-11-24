/// The marks that fit a place written bare where it needs one, as an error names them: `'consume boss' or 'copy boss'`,
/// `'copy e'`, or `'consume boss', 'copy boss' or '&boss'`.
public struct PlaceMarks: Sendable, Hashable, CustomStringConvertible {
    /// The place as the source writes it, such as `boss` or `e.stats`.
    public var place: String
    /// Whether `consume` fits: the code may move the value out of the place.
    public var mayMove: Bool
    /// Whether `&` fits: lending the place reaches a function that borrows it.
    public var mayLend: Bool

    public init(_ place: String, mayMove: Bool, mayLend: Bool) {
        self.place = place
        self.mayMove = mayMove
        self.mayLend = mayLend
    }

    public var description: String {
        let consume = mayMove ? ["'consume \(place)'"] : []
        let lend = mayLend ? ["'&\(place)'"] : []
        let marks = consume + ["'copy \(place)'"] + lend
        guard let last = marks.last, marks.count > 1 else { return marks.joined() }
        return marks.dropLast().joined(separator: ", ") + " or " + last
    }
}
