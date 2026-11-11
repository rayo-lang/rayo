import PackageGraph
import SwiftParser
import SwiftSyntax

/// The check that only the modules allowed to import LLVM's C modules do.
public struct LLVMImportCheck: Sendable {
    /// LLVM's C modules: its C API, and the JIT that the tests run code through.
    public static let cModules: Set<String> = ["CLLVM", "CLLVMJIT"]

    /// The modules that may import LLVM's C modules.
    public let allowedModules: Set<String>

    public init(allowedModules: Set<String>) {
        self.allowedModules = allowedModules
    }

    /// Returns the imports of LLVM's C modules, in order of path and line, that `files`, a package's Swift files by
    /// path, make from modules of `package` that aren't allowed them.
    public func violations(in files: [String: String], of package: PackageTargets) -> [ImportViolation] {
        files.sorted { $0.key < $1.key }.flatMap { path, source in violations(in: source, at: path, of: package) }
    }

    /// Returns the imports of LLVM's C modules, in order of line, that `source`, the file at `path`, makes where its
    /// module in `package` isn't allowed them.
    private func violations(in source: String, at path: String, of package: PackageTargets) -> [ImportViolation] {
        // A file in no target's directory is compiled into no module, and an allowed module's imports are its own.
        guard let module = package.target(holding: path), !allowedModules.contains(module) else { return [] }

        // Every import whose module is one of LLVM's C modules, or a submodule or a declaration of one, is a
        // violation, at the line of its `import`.
        let tree = Parser.parse(source: source)
        let lines = SourceLocationConverter(fileName: path, tree: tree)
        return ImportCollector.imports(in: tree).compactMap { declaration in
            guard let imported = declaration.path.first?.name.text, Self.cModules.contains(imported) else { return nil }
            let line = declaration.importKeyword.startLocation(converter: lines).line
            return ImportViolation(path: path, line: line, module: module, imported: imported)
        }
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
