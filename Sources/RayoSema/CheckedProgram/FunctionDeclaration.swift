/// What a program declares of a function: how a call reaches it, and what kind of function it is.
public struct FunctionDeclaration: Equatable, Sendable {
    /// The function's name and parameters, such as `f(_: Int)`, which no other function of the program has.
    public var name: String
    /// The parameters' types, in order.
    public var parameters: [RayoType]
    public var result: RayoType
    public var kind: FunctionKind

    public init(name: String, parameters: [RayoType], result: RayoType, kind: FunctionKind) {
        self.name = name
        self.parameters = parameters
        self.result = result
        self.kind = kind
    }
}

/// What kind of function a declaration declares, which says where its body comes from.
public enum FunctionKind: Equatable, Sendable {
    /// A function the source writes, with the body it writes.
    case written
}
