import RayoDiagnostics
import RayoSource

/// The names a function body sees: its locals and parameters, block by block, and the module's functions and
/// structs.
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
    /// functions and structs. A call gets the module's functions or struct where it has either; any other use gets
    /// the local or parameter where there is one.
    func lookUp(_ name: String, for use: NameUse) -> NameMatch? {
        // Find the name in scope and in the module; the use picks between them.
        let inScope = scopeEntry(for: name).map { NameMatch.inScope($0) }
        let module = moduleMatch(for: name)
        return switch use {
        // No local can be called, so a function or a struct wins even over a local whose declaration failed.
        case .call: module ?? inScope
        // A local or parameter shadows the module's functions and structs.
        case .ordinary: inScope ?? module
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

    /// The module's functions called `name`, or else its struct of that name, nil when it has neither.
    private func moduleMatch(for name: String) -> NameMatch? {
        let functions = file.declarations.functions(named: name)
        return if !functions.isEmpty {
            // A name the functions have is theirs, even where a struct also has it, which was reported.
            .functions(functions)
        } else {
            // Any other name is the struct's, if one has it.
            file.declarations.structure(named: name).map { .structure($0) }
        }
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
