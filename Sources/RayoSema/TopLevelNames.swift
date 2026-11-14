import RayoSource
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

    /// Where the first type of each name starts.
    private let firstTypes: [String: SourceLocation]
    /// Where the first function of each name starts.
    private let firstFunctions: [String: SourceLocation]

    /// The names of `file`'s declarations, those that failed to parse with a name among them.
    init(of file: SourceFile) {
        firstTypes = Self.firstStarts(of: TypeDeclaration.all(in: file).map { ($0.name, $0.nameRange.start) })
        let functions = file.functions.map { ($0.name, $0.nameRange.start) } + Self.unparsedFunctions(of: file)
        firstFunctions = Self.firstStarts(of: functions)
    }

    /// The names and starts of `file`'s functions that failed to parse with a name. A declaration that failed starts
    /// at its keyword, which, like a name, lies after every declaration before it and before every one after it.
    private static func unparsedFunctions(of file: SourceFile) -> [(String, SourceLocation)] {
        file.failedDeclarations.compactMap { declaration in
            guard declaration.kind == .function else { return nil }
            return declaration.name.map { ($0, declaration.range.start) }
        }
    }

    /// The kind `name` belongs to, nil when no type or function has it.
    func kind(of name: String) -> Kind? {
        switch (firstTypes[name], firstFunctions[name]) {
        case (nil, nil): nil
        case (.some, nil): .type
        case (nil, .some): .functions
        case (let typeStart?, let functionStart?): typeStart < functionStart ? .type : .functions
        }
    }

    /// Maps each name in `declarations`, which give names and starts, to the start of its first declaration.
    private static func firstStarts(of declarations: [(String, SourceLocation)]) -> [String: SourceLocation] {
        Dictionary(declarations, uniquingKeysWith: min)
    }
}
