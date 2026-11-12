import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own structs, with their fields, and functions,
/// the prelude's functions that none of them shadows, and the prelude's types that no struct shadows.
struct Declarations {
    private var functions: [String: [Signature]] = [:]
    private var structs: [String: StructID] = [:]
    /// Each struct's fields, in the order the struct declares them.
    private var fields: [StructID: [DeclaredField]] = [:]
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

    /// Declares the struct `id` by its name, which no other struct has.
    mutating func declare(_ id: StructID) {
        structs[id.name] = id
    }

    /// Declares `fields` as the fields of the struct `id`, in the order it declares them.
    mutating func declare(_ fields: [DeclaredField], of id: StructID) {
        self.fields[id] = fields
    }

    /// Declares the prelude's functions whose names the file's own structs and functions leave free.
    mutating func declarePrelude() {
        // A struct or a function of the file named `print` shadows the prelude's.
        if functions[Signature.print.name] == nil && structs[Signature.print.name] == nil { _ = declare(.print) }
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    func structure(named name: String) -> StructID? {
        structs[name]
    }

    /// The fields of the struct `id`, whose fields must be declared already.
    func fields(of id: StructID) -> [DeclaredField] {
        // The checker declares every struct's fields before it checks a body, which alone asks for them.
        guard let fields = fields[id] else { preconditionFailure("'\(id.name)' has no fields declared") }
        return fields
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
