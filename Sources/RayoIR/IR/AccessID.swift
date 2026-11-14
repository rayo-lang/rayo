/// An access to a place, numbered within its body. One statement begins it, and the code reaches the place through
/// it until a statement ends it.
public struct AccessID: Hashable, Comparable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }

    public static func < (left: AccessID, right: AccessID) -> Bool {
        left.index < right.index
    }
}
