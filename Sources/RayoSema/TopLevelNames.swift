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

    init(of file: SourceFile) {
        firstTypes = Self.firstStarts(of: TypeDeclaration.all(in: file).map { ($0.name, $0.nameRange.start) })
        firstFunctions = Self.firstStarts(of: file.functions.map { ($0.name, $0.nameRange.start) })
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
        Dictionary(declarations, uniquingKeysWith: { first, _ in first })
    }
}
