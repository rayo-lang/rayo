/// What a call needs to know about the function it calls.
struct Signature: CustomStringConvertible {
    var name: String
    var callee: Callee
    var parameters: [Parameter]
    var result: DeclaredResult

    static let print = Signature(name: "print", callee: .printInt,
                                 parameters: [Parameter(label: nil, type: .int, spelledType: "Int")],
                                 result: .type(.void))

    /// The name and the parameters, such as `f(_: Int, by: Bool)`, which tell the function apart from every other.
    var description: String {
        let parameterList = parameters.map { "\($0.label ?? "_"): \($0.spelledType)" }.joined(separator: ", ")
        return "\(name)(\(parameterList))"
    }

    /// Whether `other` takes arguments with the same labels and types, so no call could tell the two apart. A type
    /// that isn't known matches none, since it was reported where it is written.
    func takesArguments(like other: Signature) -> Bool {
        parameters.count == other.parameters.count && zip(parameters, other.parameters).allSatisfy { mine, theirs in
            mine.label == theirs.label && mine.type != nil && mine.type == theirs.type
        }
    }

    /// Whether a call may pass `arguments`, in order. A parameter whose type isn't known takes any argument, so a
    /// declaration's error doesn't spread to its calls.
    func takes(_ arguments: [(label: String?, type: RayoType)]) -> Bool {
        parameters.count == arguments.count && zip(parameters, arguments).allSatisfy { parameter, argument in
            parameter.label == argument.label && (parameter.type == nil || parameter.type == argument.type)
        }
    }
}

/// What a call needs to know about one parameter of the function it calls.
struct Parameter {
    /// The label an argument for it is written with, or nil when it is written with none.
    var label: String?
    /// The type, or nil when the declaration names no type, which was reported there.
    var type: RayoType?
    /// The type as the declaration writes it.
    var spelledType: String
}

/// A function's result type, as its declaration gives it.
enum DeclaredResult {
    case type(RayoType)
    /// A written type that names no type, or one that `main` can't return, which was reported there.
    case failed
    /// None written, on a body that is a single expression, whose type is the result type.
    case givenByBody(FunctionID)

    /// The type, when the declaration alone gives it.
    var type: RayoType? {
        // A result that failed, or that the body gives, has none.
        guard case .type(let type) = self else { return nil }
        return type
    }
}
