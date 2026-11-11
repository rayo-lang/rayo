/// An import of one of LLVM's C modules by a module that isn't allowed to import it.
public struct ImportViolation: Equatable, Sendable {
    /// The file that holds the import, relative to the package's root.
    public let path: String
    public let line: Int
    /// The module the file is compiled into.
    public let module: String
    /// The C module imported.
    public let imported: String

    public init(path: String, line: Int, module: String, imported: String) {
        self.path = path
        self.line = line
        self.module = module
        self.imported = imported
    }

    /// The violation as one line that names the file, the line, the import, and `allowedModules`, the modules that
    /// may make it.
    public func description(allowing allowedModules: Set<String>) -> String {
        "\(path):\(line): \(module) imports \(imported), which only \(Self.list(allowedModules.sorted())) may import"
    }

    /// `names` as English lists them: "A", "A and B", "A, B and C".
    private static func list(_ names: [String]) -> String {
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
