import RayoDiagnostics
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own structs and functions, and the prelude's
/// that none of them shadows.
struct Declarations {
    private var functions: [String: [Signature]] = [:]
    private var structs: [String: StructID] = [:]
    private static let preludeTypes: [String: RayoType] = ["Int": .int, "Bool": .bool, "Void": .void]

    /// Declares `signature`, unless a function with its name, labels and parameter types is declared already, and
    /// returns whether it did.
    mutating func declare(_ signature: Signature) -> Bool {
        let others = functions[signature.name, default: []]
        // No call could tell the two apart.
        guard !others.contains(where: { $0.takesArguments(like: signature) }) else { return false }
        functions[signature.name] = others + [signature]
        return true
    }

    /// Declares the struct `id` by its name, which no other struct has.
    mutating func declare(_ id: StructID) {
        structs[id.name] = id
    }

    /// Declares the prelude's functions whose names the file's own structs and functions leave free.
    mutating func declarePrelude() {
        let name = Signature.print.name
        // A struct or a function of the file named `print` shadows the prelude's.
        if functions[name] == nil && structs[name] == nil { _ = declare(.print) }
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    func structure(named name: String) -> StructID? {
        structs[name]
    }

    /// The type that `type` names: one of the file's structs, which shadow the prelude's types, or one of those.
    /// Reports a name that names no type, and returns nil for it.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void:
            return .void

        // A name names one of the file's structs, or one of the prelude's types.
        case .named(let name, let range):
            // A struct shadows the prelude's type of its name.
            if let id = structs[name] { return .structure(id) }
            // A name that is neither names no type.
            guard let resolved = Self.preludeTypes[name] else {
                errors.report(.notAType(name: name), at: range)
                return nil
            }
            return resolved
        }
    }
}
