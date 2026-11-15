import RayoSyntax

/// Which kind of declaration each of a file's top-level names belongs to. A name names one type, or functions: it
/// belongs to the kind that declares it first, and a declaration of the other kind with that name is an error.
struct TopLevelNames {
    /// The kind of declaration a name belongs to.
    enum Kind: Equatable {
        /// A type, of whichever kind declares it.
        case type
        case functions
    }

    private let kinds: [String: Kind]

    /// The names of `file`'s declarations, those that failed to parse with a name among them.
    init(of file: SourceFile) {
        var kinds: [String: Kind] = [:]
        // The file's declarations are in source order, so the first to declare a name gives it its kind.
        for declaration in file.declarations {
            guard let name = declaration.name, kinds[name] == nil else { continue }
            kinds[name] = declaration.declaresType ? .type : .functions
        }
        self.kinds = kinds
    }

    /// The kind `name` belongs to, nil when no type or function has it.
    func kind(of name: String) -> Kind? {
        kinds[name]
    }
}
