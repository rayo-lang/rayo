import RayoSource
import RayoSyntax

/// Which kind of declaration each of a file's top-level names belongs to. A name names one struct, or functions: it
/// belongs to the kind that declares it first, and a declaration of the other kind with that name is an error.
struct TopLevelNames {
    /// The kind of declaration a name belongs to.
    enum Kind: Equatable {
        case structure
        case functions
    }

    /// Where the first struct of each name starts.
    private let firstStructs: [String: SourceLocation]
    /// Where the first function of each name starts.
    private let firstFunctions: [String: SourceLocation]

    init(of file: SourceFile) {
        firstStructs = Self.firstStarts(of: file.structs.map { ($0.name, $0.nameRange.start) })
        firstFunctions = Self.firstStarts(of: file.functions.map { ($0.name, $0.nameRange.start) })
    }

    /// The kind `name` belongs to, nil when no struct or function has it.
    func kind(of name: String) -> Kind? {
        switch (firstStructs[name], firstFunctions[name]) {
        case (nil, nil): nil
        case (.some, nil): .structure
        case (nil, .some): .functions
        case (let structStart?, let functionStart?): structStart < functionStart ? .structure : .functions
        }
    }

    /// Maps each name to where its first declaration in `declarations`, each given by its name and start, starts.
    private static func firstStarts(of declarations: [(String, SourceLocation)]) -> [String: SourceLocation] {
        Dictionary(declarations, uniquingKeysWith: { first, _ in first })
    }
}
