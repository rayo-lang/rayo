import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own structs and functions, the prelude's
/// functions that none of them shadows, and the prelude's types that no struct shadows.
struct Declarations {
    private var functions: [String: [Signature]] = [:]
    private var structs: [String: StructID] = [:]
    private static let preludeTypes: [String: RayoType] = ["Int": .int, "Bool": .bool, "Void": .void]
    private static let preludeFunctions: [Signature] = [.printInt, .printBool]

    /// Declares `signature`, unless a function with its name, labels and parameter types is declared already, and
    /// returns whether it did.
    mutating func declare(_ signature: Signature) -> Bool {
        let others = functions[signature.name, default: []]
        // A function whose labels and parameter types match one declared already isn't declared.
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
        // A struct or a function of the file shadows every prelude function of its name, so the names are tested
        // before any of the prelude's is declared.
        let unshadowed = Self.preludeFunctions.filter { functions[$0.name] == nil && structs[$0.name] == nil }
        for signature in unshadowed { _ = declare(signature) }
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    func structure(named name: String) -> StructID? {
        structs[name]
    }

    /// The type that `type` names, or nil after reporting a name that names no type.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void: .void
        // A name names one of the file's structs, or one of the prelude's types.
        case .named(let name, let range): resolve(named: name, at: range, reporting: errors)
        }
    }

    /// Resolves `name` to one of the file's structs or one of the prelude's types, or reports that `name`, written
    /// at `range`, names neither, and returns nil.
    private func resolve(named name: String, at range: SourceRange, reporting errors: ErrorList) -> RayoType? {
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
