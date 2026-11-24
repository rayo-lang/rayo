/// What a move takes out of an array's element, with the array, as an error names it: `an element out of
/// 'wave.enemies'`, `'stats' out of an element of 'wave.enemies'`, or `a part out of an element of 'grid'`.
public struct ElementPart: Sendable, Hashable, CustomStringConvertible {
    /// How much of the element a move takes.
    public enum Taken: Sendable, Hashable {
        /// The whole element.
        case element
        /// A part inside the element, as the source writes it from the element, such as `stats.hp` or `slots[0]`.
        case named(String)
        /// A part inside the element that the source can't write from the element: an element of the element, or a
        /// part that an index known only when the program runs leads to.
        case unnamed
    }

    public var taken: Taken
    /// The array as the source names it, such as `wave.enemies`, or nil where the array is a value the source gives
    /// no name, such as a call's result.
    public var array: String?

    public init(_ taken: Taken, of array: String?) {
        self.taken = taken
        self.array = array
    }

    public var description: String {
        let array = array.map { "'\($0)'" } ?? "an array"
        return switch taken {
        case .element: "an element out of \(array)"
        case .named(let part): "'\(part)' out of an element of \(array)"
        case .unnamed: "a part out of an element of \(array)"
        }
    }
}
