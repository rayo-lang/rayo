/// How a value lies in memory: the bytes it takes, and the alignment its address is a multiple of. The size is a
/// multiple of the alignment, so values of the type lie one after another in an array.
public struct Layout: Hashable, Sendable {
    public var size: Int
    public var alignment: Int

    public init(size: Int, alignment: Int) {
        self.size = size
        self.alignment = alignment
    }

    public static let int = Layout(size: 8, alignment: 8)
    public static let uint = Layout(size: 8, alignment: 8)
    public static let bool = Layout(size: 1, alignment: 1)
}
