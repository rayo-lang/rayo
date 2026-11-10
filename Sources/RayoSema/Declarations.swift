import RayoDiagnostics
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own functions, the prelude's that none
/// of them shadows, and the prelude's types.
struct Declarations {
    private var functions: [String: [Signature]] = [:]
    private static let preludeTypes: [String: RayoType] = ["Int": .int, "Bool": .bool, "Void": .void]

    /// Declares `signature`, unless a function with its name, labels and parameter types is declared already, and
    /// returns whether it did.
    mutating func declare(_ signature: Signature) -> Bool {
        let others = functions[signature.name, default: []]
        // A function whose labels and parameter types match one declared already isn't declared.
        guard !others.contains(where: { $0.takesArguments(like: signature) }) else { return false }
        functions[signature.name] = others + [signature]
        return true
    }

    /// Declares the prelude's functions whose names the file's own functions leave free.
    mutating func declarePrelude() {
        // A function of the file named `print` shadows the prelude's.
        if functions[Signature.print.name] == nil { _ = declare(.print) }
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    /// The type that `type` names, or nil after reporting a name that names no type.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void:
            return .void

        // A name names one of the prelude's types.
        case .named(let name, let range):
            // A name that isn't one of them names no type.
            guard let resolved = Self.preludeTypes[name] else {
                errors.report(.notAType(name: name), at: range)
                return nil
            }
            return resolved
        }
    }
}
