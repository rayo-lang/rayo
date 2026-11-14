/// The functions a program declares, each named by its `FunctionID`. A function whose declaration failed keeps its ID,
/// with no declaration under it, and no body of the program reaches it.
public struct FunctionTable: Equatable, Sendable {
    /// The declarations, indexed by `FunctionID`, nil for a function whose declaration failed.
    private var declarations: [FunctionDeclaration?] = []

    /// A table that declares no function.
    public init() {}

    /// The ID of each function whose declaration checked, in the order the table declared them.
    public var ids: [FunctionID] {
        declarations.indices.filter { declarations[$0] != nil }.map { FunctionID(index: $0) }
    }

    /// The declaration of the function `id`, which must have checked.
    public subscript(id: FunctionID) -> FunctionDeclaration {
        // A body that reaches a failed declaration is tainted, and no stage after checking sees it.
        guard let declaration = declarations[id.index] else {
            preconditionFailure("function \(id.index) failed to declare, so no checked program reaches it")
        }
        return declaration
    }

    /// Adds `declaration` to the table, and returns its ID, which comes after every function declared before it.
    public mutating func declare(_ declaration: FunctionDeclaration) -> FunctionID {
        declarations.append(declaration)
        return FunctionID(index: declarations.count - 1)
    }

    /// Adds a function whose declaration failed to the table, and returns its ID, which comes after every function
    /// declared before it.
    public mutating func declareFailed() -> FunctionID {
        declarations.append(nil)
        return FunctionID(index: declarations.count - 1)
    }
}
