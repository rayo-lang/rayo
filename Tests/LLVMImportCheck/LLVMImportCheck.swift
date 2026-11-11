import PackageGraph
import SwiftParser
import SwiftSyntax

/// A check of the imports of LLVM's C modules: only the modules it allows may make them, and none may re-export
/// them.
public struct LLVMImportCheck: Sendable {
    /// LLVM's C modules: its C API, and the JIT that the tests run code through.
    private static let cModules: Set<String> = ["CLLVM", "CLLVMJIT"]

    /// The modules that may import LLVM's C modules.
    private let allowedModules: Set<String>

    public init(allowedModules: Set<String>) {
        self.allowedModules = allowedModules
    }

    /// Returns the imports of LLVM's C modules in `files`, a package's Swift files by path, that their modules in
    /// `package` may not make, in order of path and line.
    public func violations(in files: [String: String], of package: PackageTargets) -> [ImportViolation] {
        files.sorted { $0.key < $1.key }.flatMap { path, source in violations(in: source, at: path, of: package) }
    }

    /// Describes `violation` in one line, by its file, its line and its import, and why the import is one.
    public func description(of violation: ImportViolation) -> String {
        let place = "\(violation.path):\(violation.line): \(violation.module)"

        switch violation.kind {
        // An import by a module off the list names the modules on it.
        case .notAllowed:
            return "\(place) imports \(violation.imported), which only \(Self.list(allowedModules.sorted())) may import"
        // A re-export names the modules it hands the C module to.
        case .reexported:
            return "\(place) re-exports \(violation.imported), which hands it to every module that imports "
                + violation.module
        }
    }

    /// Returns the imports of LLVM's C modules in `source`, the file at `path`, that its module in `package` may not
    /// make, in order of line.
    private func violations(in source: String, at path: String, of package: PackageTargets) -> [ImportViolation] {
        // A file in no target's directory is compiled into no module, so it imports nothing.
        guard let module = package.target(holding: path) else { return [] }

        // Each import of one of LLVM's C modules, or of a submodule or a declaration of one, is checked at the line
        // of its `import`.
        let isAllowed = allowedModules.contains(module)
        let tree = Parser.parse(source: source)
        let lines = SourceLocationConverter(fileName: path, tree: tree)
        return ImportCollector.imports(in: tree).compactMap { declaration in
            // An import of any other module is no violation.
            guard let imported = declaration.path.first?.name.text, Self.cModules.contains(imported) else { return nil }
            let line = declaration.importKeyword.startLocation(converter: lines).line
            // A re-export hands the C module to every module that imports this one, so no module may make one.
            if Self.reexports(declaration) {
                return ImportViolation(kind: .reexported, path: path, line: line, module: module, imported: imported)
            }
            // A module allowed to import the C modules may.
            guard !isAllowed else { return nil }
            return ImportViolation(kind: .notAllowed, path: path, line: line, module: module, imported: imported)
        }
    }

    /// Whether `declaration` re-exports the module it imports, which `@_exported` marks it to.
    private static func reexports(_ declaration: ImportDeclSyntax) -> Bool {
        declaration.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported" }
    }

    /// `names` as English lists them: "A", "A and B", "A, B and C".
    private static func list(_ names: [String]) -> String {
        // No name, or one, is its own list.
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}

/// Collects the import declarations of a syntax tree, those in each clause of an `#if` among them.
private final class ImportCollector: SyntaxVisitor {
    private var imports: [ImportDeclSyntax] = []

    /// Returns the import declarations of `tree`, in order.
    static func imports(in tree: SourceFileSyntax) -> [ImportDeclSyntax] {
        let collector = ImportCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.imports
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node)
        return .skipChildren
    }
}
