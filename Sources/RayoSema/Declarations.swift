import RayoDiagnostics
import RayoSyntax

/// What a call needs to know about the function it calls.
struct Signature: CustomStringConvertible {
    var name: String
    var callee: Callee
    var parameters: [RayoType]
    var result: DeclaredResult

    static let print = Signature(name: "print", callee: .printInt, parameters: [.int], result: .type(.void))

    /// The name and the parameters, such as `f()`, which tell the function apart from every other.
    var description: String { "\(name)()" }
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
    private var functions: [String: Signature] = [:]

    /// Declares `signature`, unless a function of its name is declared already, and returns whether it did.
    mutating func declare(_ signature: Signature) -> Bool {
        guard functions[signature.name] == nil else { return false }
        functions[signature.name] = signature
        return true
    }

    func function(named name: String) -> Signature? {
        functions[name]
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
