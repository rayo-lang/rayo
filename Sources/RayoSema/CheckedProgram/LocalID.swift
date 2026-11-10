/// Identifies a local of a function.
public struct LocalID: Hashable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}
