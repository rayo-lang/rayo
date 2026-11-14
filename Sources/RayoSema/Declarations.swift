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
    /// Each struct's initializers, which a call of the struct's name reaches. A struct without one is made by its
    /// primary initializer.
    private var initializers: [StructID: [Signature]] = [:]
    /// The primary initializer of each struct that can be laid out.
    private var primaryInitializers: [StructID: FunctionID] = [:]
    /// Each struct's fields, in the order the struct declares them.
    private var fields: [StructID: [DeclaredField]] = [:]
    /// The structs that can't be laid out, whose uses report nothing more.
    private var unlaidOutStructs: Set<StructID> = []
    /// The names of the functions that failed to parse, whose uses report nothing more.
    private var unparsedFunctions: Set<String> = []
    /// The structs that can be laid out, which lay out every type that holds them; nil until the structs are
    /// checked, while their fields' types are resolved.
    private var layouts: TypeTable?
    private static let preludeTypes: [String: RayoType] = [
        "Int": .int, "UInt": .uint, "Bool": .bool, "Void": .void,
    ]

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

    /// Declares `types`, the structs that can be laid out, so that each type resolved from here on is checked to
    /// fit in memory.
    mutating func declareLayouts(_ types: TypeTable) {
        layouts = types
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

    /// Declares the function `initializer` as the primary initializer of the struct `id`.
    mutating func declarePrimaryInitializer(_ initializer: FunctionID, of id: StructID) {
        primaryInitializers[id] = initializer
    }

    /// Declares the prelude's built-ins whose names the file's own types and functions leave free.
    mutating func declarePrelude() {
        // A type or a function of the file shadows every prelude function that a call reaches by its name.
        for signature in Builtin.allCases.map(Signature.init(of:)) where kind(of: signature.name) == nil {
            _ = declare(signature)
        }
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

    /// The primary initializer of the struct `id`, which must be laid out.
    func primaryInitializer(of id: StructID) -> FunctionID {
        // The checker declares the primary initializer of every struct that can be laid out before it checks a body,
        // and a body reaches no struct that can't.
        guard let initializer = primaryInitializers[id] else {
            preconditionFailure("'\(id.name)' has no primary initializer declared")
        }
        return initializer
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
        case .int, .uint, .bool, .void: kind(of: name) == nil ? .named(name) : .shadowedPrelude(name)
        // An array is named by its count and its element's name.
        case .array(let count, let element): .named("[\(count) of \(typeName(of: element))]")
        }
    }

    /// The type that `type` names, or nil after reporting a name that names no type, or an array that can't be.
    func resolve(_ type: TypeExpr, reporting errors: ErrorList) -> RayoType? {
        switch type {
        // `()` is Void.
        case .void: .void
        // A name names one of the file's types, or one of the prelude's types that no function shadows.
        case .named(let name, let range): resolve(named: name, at: range, reporting: errors)
        // An array holds values of its element's type.
        case .array(let count, let element, let range):
            resolveArray(of: count, element, at: range, reporting: errors)
        }
    }

    /// The array of `count` values of the type `element` names, which the source writes at `range`, or nil after
    /// reporting an element type that names no type or names Void, or an array whose size in bytes doesn't fit in
    /// an Int.
    private func resolveArray(
        of count: UInt64, _ element: TypeExpr, at range: SourceRange, reporting errors: ErrorList,
    ) -> RayoType? {
        // An element type that names no type was reported.
        guard let elementType = resolve(element, reporting: errors) else { return nil }
        // No element holds a Void value.
        guard elementType != .void else {
            errors.report(.voidElement(type: typeName(of: .void)), at: element.range)
            return nil
        }

        // An array's size in bytes must fit in an Int, which counts its elements too, even ones that take no memory.
        // A field's array is resolved before the structs are laid out, so its size is checked with its struct's.
        let array = Int(exactly: count).map { RayoType.array(count: $0, element: elementType) }
        guard let array, layouts?.fitsInMemory(array) ?? true else {
            errors.report(.arrayTooLarge, at: range)
            return nil
        }
        return array
    }

    /// Resolves `name` to one of the file's types or one of the prelude's types that no function shadows, or
    /// reports that `name`, written at `range`, names neither, and returns nil.
    private func resolve(named name: String, at range: SourceRange, reporting errors: ErrorList) -> RayoType? {
        // A type of the file shadows the prelude's type of its name. One that failed names no type, and taints the body
        // that names it, which reports nothing more.
        if let declared = types[name] {
            // A struct that can't be laid out has a type, which no stage after checking can use, so it names none.
            guard !hasFailedType(named: name) else {
                errors.taints.taint()
                return nil
            }
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
