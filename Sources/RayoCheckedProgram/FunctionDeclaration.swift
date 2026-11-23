/// What a program declares of a function: how a call reaches it, and what kind of function it is.
public struct FunctionDeclaration: Equatable, Sendable {
    /// The function's name and parameters, such as `f(_: Int)`, which no other function of the program has.
    public var name: String
    /// The parameters, in order.
    public var parameters: [FunctionParameter]
    public var result: RayoType
    public var kind: FunctionKind

    public init(name: String, parameters: [FunctionParameter], result: RayoType, kind: FunctionKind) {
        self.name = name
        self.parameters = parameters
        self.result = result
        self.kind = kind
    }

    /// The name of a function called `base`, spelling each parameter's label, convention and type: `f(_: &Int)`.
    package static func name(_ base: String, parameters: [FunctionParameter]) -> String {
        name(base, parameters: parameters.map { (label: $0.label, type: $0.convention.spelling(of: $0.type)) })
    }

    /// The name of a function called `base`, given each parameter's label and its type as already spelled, such as
    /// `&Int`.
    package static func name(_ base: String, parameters: [(label: String?, type: String)]) -> String {
        let parameterList = parameters.map { "\($0.label ?? "_"): \($0.type)" }.joined(separator: ", ")
        return "\(base)(\(parameterList))"
    }
}

/// What kind of function a declaration declares.
public enum FunctionKind: Equatable, Sendable {
    /// A function the source writes.
    case written
    /// A struct's primary initializer, which the struct declares with no body: it takes each field's value, owned,
    /// in the order the struct declares its fields, and makes the struct of them.
    case primaryInitializer(StructID)

    /// The word the program's text starts the declaration with: `func` for a function the source writes, and `init`
    /// for a primary initializer.
    package var keyword: String {
        switch self {
        case .written: "func"
        case .primaryInitializer: "init"
        }
    }
}
