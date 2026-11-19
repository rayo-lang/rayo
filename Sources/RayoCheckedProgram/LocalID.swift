/// Identifies a local of a function. Locals order as their indices do.
public struct LocalID: Hashable, Comparable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }

    public static func < (left: LocalID, right: LocalID) -> Bool {
        left.index < right.index
    }
}
