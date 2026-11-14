import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own types, with each struct's fields,
/// and functions, and the prelude's functions and types that none of them shadows.
struct Declarations {
    /// The file's top-level names, known before any of its declarations is declared.
    private let names: TopLevelNames
    private var functions: [String: [Signature]] = [:]
    /// The file's types of every kind, which share one namespace.
    private var types: [String: DeclaredType] = [:]
    /// Each struct's initializers, which a call of the struct's name reaches. A struct without one is made from its
    /// fields' values.
    private var initializers: [StructID: [Signature]] = [:]
    /// Each struct's fields, in the order the struct declares them.
    private var fields: [StructID: [DeclaredField]] = [:]
    /// The structs that can't be laid out, whose uses report nothing more.
    private var unlaidOutStructs: Set<StructID> = []
    /// The names of the functions that failed to parse, whose uses report nothing more.
    private var unparsedFunctions: Set<String> = []
    private static let preludeTypes: [String: RayoType] = ["Int": .int, "Bool": .bool, "Void": .void]

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

    /// Declares `type` by its name, which no other type has.
    mutating func declare(_ type: DeclaredType) {
        types[type.name] = type
    }

    /// Declares the struct `id` as one that can't be laid out, whose uses report nothing more.
    mutating func declareUnlaidOut(_ id: StructID) {
        unlaidOutStructs.insert(id)
    }

    /// Declares `name` as the name of a function that failed to parse, whose uses report nothing more.
    mutating func declareUnparsedFunction(named name: String) {
        unparsedFunctions.insert(name)
    }

    /// Whether a function called `name` failed to parse.
    func hasFailedFunction(named name: String) -> Bool {
        unparsedFunctions.contains(name)
    }

    /// Whether the type called `name` failed to parse, or is a struct that can't be laid out.
    func hasFailedType(named name: String) -> Bool {
        switch types[name] {
        case .failed: true
        case .structure(let id): unlaidOutStructs.contains(id)
        case nil: false
        }
    }

    /// Declares `fields` as the fields of the struct `id`, in the order it declares them.
    mutating func declare(_ fields: [DeclaredField], of id: StructID) {
        self.fields[id] = fields
    }

    /// Declares the prelude's built-ins whose names the file's own types and functions leave free.
    mutating func declarePrelude() {
        declarePrelude(Builtin.allCases.map(Signature.init(of:)))
    }

    /// Declares each of `signatures`, the prelude's, whose name the file's own types and functions leave free.
    mutating func declarePrelude(_ signatures: [Signature]) {
        // A type or a function of the file shadows every prelude function that a call reaches by its name.
        for signature in signatures where kind(of: signature.name) == nil { _ = declare(signature) }
    }

    /// The kind of the file's declarations that `name` belongs to, nil when no type or function of the file has it.
    func kind(of name: String) -> TopLevelNames.Kind? {
        names.kind(of: name)
    }

    func functions(named name: String) -> [Signature] {
        functions[name, default: []]
    }

    func initializers(of id: StructID) -> [Signature] {
        initializers[id, default: []]
    }

    func type(named name: String) -> DeclaredType? {
        types[name]
    }

    /// The fields of the struct `id`, whose fields must be declared already.
    func fields(of id: StructID) -> [DeclaredField] {
        // The checker declares every struct's fields before it checks a body, which alone asks for them.
        guard let fields = fields[id] else { preconditionFailure("'\(id.name)' has no fields declared") }
        return fields
    }

    /// The name an error gives `type`, which tells a prelude type apart from the file's declaration of its name.
    func typeName(of type: RayoType) -> TypeName {
        let name = type.description

        return switch type {
        // A struct is the file's own, so its name alone tells it apart.
        case .structure: .named(name)
        // A prelude type is shadowed where a type or a function of the file has its name.
        case .int, .bool, .void: kind(of: name) == nil ? .named(name) : .shadowedPrelude(name)
        }
    }

    /// The type that `type` names, or nil after reporting a name that names no type.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void: .void
        // A name names one of the file's types, or one of the prelude's types that no function shadows.
        case .named(let name, let range): resolve(named: name, at: range, reporting: errors)
        }
    }

    /// Resolves `name` to one of the file's types or one of the prelude's types that no function shadows, or
    /// reports that `name`, written at `range`, names neither, and returns nil.
    private func resolve(named name: String, at range: SourceRange, reporting errors: ErrorList) -> RayoType? {
        // A type of the file shadows the prelude's type of its name. One that failed names no type, and taints the body
        // that names it, which reports nothing more.
        if let declared = types[name] {
            if hasFailedType(named: name) { errors.taints.taint() }
            return declared.type
        }
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
