/// The functions a program declares, each named by its `FunctionID`.
public struct FunctionTable: Equatable, Sendable {
    /// The declarations, indexed by `FunctionID`.
    private var declarations: [FunctionDeclaration] = []

    /// A table that declares no function.
    public init() {}

    /// The ID of each function, in the order the table declared them.
    public var ids: [FunctionID] {
        declarations.indices.map { FunctionID(index: $0) }
    }

    public subscript(id: FunctionID) -> FunctionDeclaration {
        declarations[id.index]
    }

    /// Adds `declaration` to the table, and returns its ID, which comes after every function declared before it.
    public mutating func declare(_ declaration: FunctionDeclaration) -> FunctionID {
        declarations.append(declaration)
        return FunctionID(index: declarations.count - 1)
    }
}
