import RayoDiagnostics
import RayoSource

/// The names a function body sees: its locals and parameters, block by block, and the module's functions.
final class NameScopes {
    private let file: FileChecker
    /// The body's locals, indexed by `LocalID`.
    private(set) var locals: [CheckedLocal] = []
    /// The names each enclosing block declares, innermost last, inside the scope of the function's parameters.
    private var blocks: [[String: ScopeEntry]] = [[:]]

    init(file: FileChecker) {
        self.file = file
    }

    subscript(local: LocalID) -> CheckedLocal {
        locals[local.index]
    }

    /// Starts a block, whose names go out of scope when it ends.
    func enterBlock() {
        blocks.append([:])
    }

    func leaveBlock() {
        blocks.removeLast()
    }

    /// Looks `name` up among the body's locals and parameters, innermost block first, and among the module's
    /// functions. A call gets the functions where there are any; any other use gets the local or parameter where
    /// there is one.
    func lookUp(_ name: String, for use: NameUse) -> NameMatch? {
        // Find the name in scope and among the functions; the use picks between them.
        let inScope = scopeEntry(for: name).map { NameMatch.inScope($0) }
        let functions = functionMatch(for: name)
        switch use {
        // No local can be called, so a function wins even over a local whose declaration failed.
        case .call:
            return functions ?? inScope

        // A local or parameter shadows the module's functions.
        case .ordinary:
            return inScope ?? functions
        }
    }

    /// Declares `name` in the innermost block as a new local of `type`, or, when `type` is nil or the name is
    /// declared already, as a failed declaration, whose uses report nothing more.
    func declare(_ name: String, type: RayoType?, kind: LocalKind, at range: SourceRange) -> LocalID? {
        // A name declared already in scope is reported, and its new declaration fails.
        guard !isDeclared(name, reportingRedeclarationAt: range) else {
            declareFailed(name)
            return nil
        }
        // A declaration whose type isn't known fails too; what left it without one was reported.
        guard let type else {
            declareFailed(name)
            return nil
        }

        // Add the local to the body's, under its name in the innermost block.
        let local = LocalID(index: locals.count)
        locals.append(CheckedLocal(name: name, type: type, kind: kind))
        blocks[blocks.count - 1][name] = .local(local)
        return local
    }

    private func scopeEntry(for name: String) -> ScopeEntry? {
        blocks.reversed().lazy.compactMap { $0[name] }.first
    }

    /// The module's functions called `name`, unless it has none.
    private func functionMatch(for name: String) -> NameMatch? {
        let functions = file.declarations.functions(named: name)
        return functions.isEmpty ? nil : .functions(functions)
    }

    /// Declares `name` in the innermost block as a failed declaration, whose uses report nothing more.
    private func declareFailed(_ name: String) {
        blocks[blocks.count - 1][name] = .failed
    }

    /// Whether `name` already names a local or a parameter, even one whose declaration failed, reporting it when it
    /// does.
    private func isDeclared(_ name: String, reportingRedeclarationAt range: SourceRange) -> Bool {
        // A name in no enclosing block is free, even where a function has it.
        guard scopeEntry(for: name) != nil else { return false }
        file.errors.report(.alreadyDeclared(name: name), at: range)
        return true
    }
}
