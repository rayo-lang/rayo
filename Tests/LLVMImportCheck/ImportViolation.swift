/// An import of one of LLVM's C modules that a module may not make.
public struct ImportViolation: Equatable, Sendable {
    /// What makes an import a violation.
    public enum Kind: Equatable, Sendable {
        /// The module isn't one of those allowed to import LLVM's C modules.
        case notAllowed
        /// The import re-exports the C module, which hands it to every module that imports this one.
        case reexported
    }

    public let kind: Kind
    /// The file that holds the import, relative to the package's root.
    public let path: String
    public let line: Int
    /// The module the file is compiled into.
    public let module: String
    /// The C module imported.
    public let imported: String

    public init(kind: Kind, path: String, line: Int, module: String, imported: String) {
        self.kind = kind
        self.path = path
        self.line = line
        self.module = module
        self.imported = imported
    }
}
