import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The names a function body sees beyond its own locals: the file's own types and functions, and the prelude's
/// functions and types that none of them shadows.
struct Declarations {
    /// The file's top-level names, known before any of its declarations is declared.
    private let names: TopLevelNames
    private var functions: [String: [Signature]] = [:]
    /// The file's types of every kind.
    var types = NamedTypes()
    /// The primary initializer of each struct that can be laid out.
    private var primaryInitializers: [StructID: Signature] = [:]
    /// The names of the functions that failed to parse, whose uses report nothing more.
    private var unparsedFunctions: Set<String> = []

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

    /// Declares `name` as the name of a function that failed to parse, whose uses report nothing more.
    mutating func declareUnparsedFunction(named name: String) {
        unparsedFunctions.insert(name)
    }

    /// Whether a function called `name` failed to parse.
    func hasFailedFunction(named name: String) -> Bool {
        unparsedFunctions.contains(name)
    }

    /// Declares the function `initializer` signs as the primary initializer of the struct `id`.
    mutating func declarePrimaryInitializer(_ initializer: Signature, of id: StructID) {
        primaryInitializers[id] = initializer
    }

    /// Declares the prelude's functions whose names the file's own types and functions leave free. A prelude type's
    /// initializers are members of the type, which a call reaches through the type.
    mutating func declarePrelude() {
        // A type or a function of the file shadows every prelude function that a call reaches by its name.
        let functions = Builtin.allCases.filter { $0.initializedType == nil }.map(Signature.init(of:))
        for signature in functions where kind(of: signature.name) == nil {
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

    /// The primary initializer of the struct `id`, which must be laid out.
    func primaryInitializer(of id: StructID) -> Signature {
        // The checker declares the primary initializer of every struct that can be laid out before it checks a body,
        // and a body reaches no struct that can't.
        guard let initializer = primaryInitializers[id] else {
            preconditionFailure("'\(id.name)' has no primary initializer declared")
        }
        return initializer
    }

    /// The prelude type called `name`, or nil where no prelude type has the name or a type or a function of the file
    /// shadows it.
    func preludeType(named name: String) -> RayoType? {
        kind(of: name) == nil ? RayoType.prelude(named: name) : nil
    }

    /// The name an error gives `type`, which tells a prelude type apart from the file's declaration of its name.
    func typeName(of type: RayoType) -> TypeName {
        let name = type.description

        return switch type {
        // A named type is the file's own, so its name alone tells it apart.
        case .named: .named(name)
        // A prelude type is shadowed where a type or a function of the file has its name.
        case .scalar, .void: kind(of: name) == nil ? .named(name) : .shadowedPrelude(name)
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
        // A field's array is resolved before the types are laid out, so its size is checked with its type's.
        let array = Int(exactly: count).map { RayoType.array(count: $0, element: elementType) }
        guard let array, types.fitsInMemory(array) else {
            errors.report(.arrayTooLarge, at: range)
            return nil
        }
        return array
    }

    /// Resolves `name` to one of the file's types or one of the prelude's types that no function shadows, or
    /// reports that `name`, written at `range`, names neither, and returns nil.
    private func resolve(named name: String, at range: SourceRange, reporting errors: ErrorList) -> RayoType? {
        // A type of the file shadows the prelude's type of its name. One that failed names no type, and taints the body
        // that names it, which reports nothing more. A type that can't be laid out has a type, which no stage after
        // checking can use, so it names none either.
        if types.isDeclared(name) {
            guard let type = types.type(named: name), !types.hasFailed(named: name) else {
                errors.taints.taint()
                return nil
            }
            return type
        }
        // A function shadows it too, though it names no type. The file's names are known before any is declared, so
        // a type written before the function is declared, such as a field's, is shadowed as well. Such a name, and
        // one that no prelude type has, names no type, and is reported where it is written.
        guard let resolved = preludeType(named: name) else {
            errors.report(.notAType(name: name), at: range)
            return nil
        }
        return resolved
    }
}
