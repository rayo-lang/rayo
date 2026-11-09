import RayoDiagnostics
import RayoSyntax

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
        "\(name)(\(parameters.map { "\($0.label ?? "_"): \($0.spelledType)" }.joined(separator: ", ")))"
    }

    /// Whether `other` takes arguments with the same labels and types, so no call could tell the two apart.
    func takesArguments(like other: Signature) -> Bool {
        parameters.map(\.label) == other.parameters.map(\.label)
            && parameters.map(\.type) == other.parameters.map(\.type)
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
        guard case .type(let type) = self else { return nil }
        return type
    }
}

/// The names a function body sees beyond its own locals: the file's own functions, and the prelude's that none
/// of them shadows.
struct Declarations {
    private var functions: [String: [Signature]] = [:]

    /// Declares `signature`, unless a function with its name, labels and parameter types is declared already, and
    /// returns whether it did.
    mutating func declare(_ signature: Signature) -> Bool {
        let others = functions[signature.name, default: []]
        guard !others.contains(where: { $0.takesArguments(like: signature) }) else { return false }
        functions[signature.name] = others + [signature]
        return true
    }

    /// Declares the prelude's functions whose names the file's own functions leave free.
    mutating func declarePrelude() {
        if functions[Signature.print.name] == nil { _ = declare(.print) }
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    func declaresFunction(named name: String) -> Bool {
        functions[name] != nil
    }

    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        case .named("Int", _):
            return .int
        case .named("Bool", _):
            return .bool
        case .named("Void", _), .void:
            return .void
        case .named(let name, let range):
            errors.report(.notAType(name: name), at: range)
            return nil
        }
    }
}
