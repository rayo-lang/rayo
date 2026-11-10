/// Identifies a struct of a program, and carries the name the program declares it by.
public struct StructID: Hashable, Sendable {
    /// Where the struct is in its program's `TypeTable`.
    public var index: Int
    public var name: String

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}
