import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own structs, with their fields, and functions,
/// and the prelude's functions and types that none of them shadows.
struct Declarations {
    /// The file's top-level names, known before any of its declarations is declared.
    private let names: TopLevelNames
    private var functions: [String: [Signature]] = [:]
    private var structs: [String: StructID] = [:]
    /// Each struct's fields, in the order the struct declares them.
    private var fields: [StructID: [DeclaredField]] = [:]
    private static let preludeTypes: [String: RayoType] = ["Int": .int, "Bool": .bool, "Void": .void]
    private static let preludeFunctions: [Signature] = [.printInt, .printBool]

    /// Declarations of a file whose top-level names are `names`, holding none of the file's declarations yet.
    init(names: TopLevelNames) {
        self.names = names
    }

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
        // A struct or a function of the file shadows every prelude function of its name.
        for signature in Self.preludeFunctions where kind(of: signature.name) == nil { _ = declare(signature) }
    }

    /// The kind of the file's declarations that `name` belongs to, nil when no struct or function of the file has it.
    func kind(of name: String) -> TopLevelNames.Kind? {
        names.kind(of: name)
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

    /// The name an error gives `type`, which tells a prelude type apart from the file's declaration of its name.
    func name(of type: RayoType) -> TypeName {
        let name = type.description

        return switch type {
        // A struct is the file's own, so its name alone tells it apart.
        case .structure: .named(name)
        // A prelude type is shadowed where a struct or a function of the file has its name.
        case .int, .bool, .void: kind(of: name) == nil ? .named(name) : .shadowedPrelude(name)
        }
    }

    /// The type that `type` names, or nil after reporting a name that names no type.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void: .void
        // A name names one of the file's structs, or one of the prelude's types that no function shadows.
        case .named(let name, let range): resolve(named: name, at: range, reporting: errors)
        }
    }

    /// Resolves `name` to one of the file's structs or one of the prelude's types that no function shadows, or
    /// reports that `name`, written at `range`, names neither, and returns nil.
    private func resolve(named name: String, at range: SourceRange, reporting errors: ErrorList) -> RayoType? {
        // A struct shadows the prelude's type of its name.
        if let id = structs[name] { return .structure(id) }
        // A function shadows it too, though it names no type. The file's names are known before any is declared, so
        // a type written before the function is declared, such as a field's, is shadowed as well.
        let isShadowedByFunction = kind(of: name) == .functions
        // Such a name, and one that no prelude type has, names no type, and is reported where it is written.
        guard !isShadowedByFunction, let resolved = Self.preludeTypes[name] else {
            errors.report(.notAType(name: name), at: range)
            return nil
        }
        return resolved
    }
}
