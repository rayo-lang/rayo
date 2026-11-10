/// Identifies a function of a program.
public struct FunctionID: Hashable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}
