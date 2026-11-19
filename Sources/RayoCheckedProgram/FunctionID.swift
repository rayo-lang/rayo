/// Identifies a function of a program by its entry in the program's `FunctionTable`.
public struct FunctionID: Hashable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}
