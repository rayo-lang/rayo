import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Diagnostics`, which gives an enum of codes a `number` and a `message` made from each case's `@Code`.
/// A table written wrong gets errors where it is wrong, and members that keep its uses compiling, so that
/// only those errors are reported.
public struct DiagnosticsMacro: MemberMacro {
    /// A member the macro generates: a property with a body for a table read without errors, and a
    /// fallback body that keeps a table written wrong compiling.
    private struct Member {
        var name: String
        var type: String
        var fallbackBody: String
        var body: ([CodeEntry]) -> String

        /// The property, with `access` before it, and its body for `entries`, or its fallback body when
        /// there are none.
        func declaration(for entries: [CodeEntry]?, access: String) -> DeclSyntax {
            """
            \(raw: access)var \(raw: name): \(raw: type) {
                \(raw: entries.map(body) ?? fallbackBody)
            }
            """
        }
    }

    /// The members the macro generates, each a `switch` over the enum's cases.
    private static var members: [Member] {
        [
            Member(name: "number", type: "Int", fallbackBody: "0") { entries in
                switchOverSelf(entries.map { "case .\($0.name): \($0.number)" })
            },
            Member(name: "message", type: "String", fallbackBody: "\"\"") { entries in
                switchOverSelf(entries.map { "case \($0.bindingPattern): \($0.messageLiteral)" })
            },
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        // Anything but an enum has no cases to number, and gets no members.
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.notAnEnum))
            return []
        }

        // Report every way the table is written wrong, so that one expansion shows them all.
        var errors: [Diagnostic] = []
        let generated = membersToGenerate(in: enumDecl, reporting: &errors)
        errors += conditionalCases(in: enumDecl)
        let entries = entries(of: enumDecl, reporting: &errors)
        errors.forEach { context.diagnose($0) }

        // A table written wrong gets the fallback bodies, which compile whatever its cases are.
        let readEntries = errors.isEmpty ? entries : nil
        return generated.map { $0.declaration(for: readEntries, access: accessModifier(of: enumDecl)) }
    }

    /// The members the macro generates that `enumDecl` doesn't declare itself, reporting each it does.
    private static func membersToGenerate(in enumDecl: EnumDeclSyntax,
                                          reporting errors: inout [Diagnostic]) -> [Member] {
        members.filter { member in
            // A member the enum doesn't declare is generated.
            guard let declaration = instanceDeclaration(named: member.name, in: enumDecl) else { return true }

            // A member the enum declares is reported, and left out, so the expansion doesn't declare it twice.
            errors.append(Diagnostic(node: declaration, message: CodeTableError.memberTaken(member.name)))
            return false
        }
    }

    /// An error at each case declared under an `#if`.
    private static func conditionalCases(in enumDecl: EnumDeclSyntax) -> [Diagnostic] {
        casesUnderIf(in: enumDecl.memberBlock.members).map {
            Diagnostic(node: $0.caseKeyword, message: CodeTableError.conditionalCase)
        }
    }

    /// Each case's entry, in order, or nil when any case has none. Reports a number used twice.
    private static func entries(of enumDecl: EnumDeclSyntax, reporting errors: inout [Diagnostic]) -> [CodeEntry]? {
        // Read every case, so that each one written wrong is reported, and check the numbers of those read.
        let cases = enumDecl.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        let entries = cases.compactMap { CodeEntry.read($0, reporting: &errors) }
        errors += duplicateNumbers(in: entries)

        // A case without an entry leaves the table without any.
        guard entries.count == cases.count else { return nil }

        return entries
    }

    /// An error at each entry whose number an earlier entry has, with a note at that earlier one.
    private static func duplicateNumbers(in entries: [CodeEntry]) -> [Diagnostic] {
        var firstUses: [Int: ExprSyntax] = [:]
        return entries.compactMap { entry in
            // The first entry with a number uses it.
            guard let firstUse = firstUses[entry.number] else {
                firstUses[entry.number] = entry.numberNode
                return nil
            }

            // A later one is an error, with a note at the first.
            let note = Note(node: Syntax(firstUse), message: CodeTableNote.firstUse(entry.number))
            let error = CodeTableError.duplicateNumber(entry.number)
            return Diagnostic(node: entry.numberNode, message: error, notes: [note])
        }
    }

    /// The cases declared under an `#if` among `members`, at any depth.
    private static func casesUnderIf(in members: MemberBlockItemListSyntax) -> [EnumCaseDeclSyntax] {
        members.flatMap { member -> [EnumCaseDeclSyntax] in
            // A member outside an `#if` holds none.
            guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else { return [] }

            return conditional.clauses.flatMap { clause -> [EnumCaseDeclSyntax] in
                // A clause that holds no declarations holds no cases.
                guard case .decls(let clauseMembers) = clause.elements else { return [] }

                // Every case in the clause is under the `#if`, and so is every case of an `#if` nested in it.
                let cases = clauseMembers.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
                return cases + casesUnderIf(in: clauseMembers)
            }
        }
    }

    /// The instance property or method of `enumDecl` named `name`, if there is one.
    private static func instanceDeclaration(named name: String, in enumDecl: EnumDeclSyntax) -> DeclSyntax? {
        enumDecl.memberBlock.members.first { member in
            // An instance property is a match when one of its bindings has the name.
            if let variable = member.decl.as(VariableDeclSyntax.self), !isStatic(variable.modifiers) {
                let patterns = variable.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self) }
                return patterns.contains { $0.identifier.text == name }
            }
            // An instance method is a match when it has the name.
            if let function = member.decl.as(FunctionDeclSyntax.self), !isStatic(function.modifiers) {
                return function.name.text == name
            }
            // Any other member, a static one among them, is no match.
            return false
        }?.decl
    }

    /// Whether `modifiers` make a member the type's, rather than each instance's.
    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    /// `public ` or `package ` when the enum is, so that its generated members are too; otherwise nothing.
    private static func accessModifier(of enumDecl: EnumDeclSyntax) -> String {
        // An enum at any other access gets members at the default one, which is no wider.
        guard let modifier = enumDecl.modifiers.first(where: { ["public", "package"].contains($0.name.text) }) else {
            return ""
        }

        return "\(modifier.name.text) "
    }

    /// A `switch self` with each of `cases` on a line of its own.
    private static func switchOverSelf(_ cases: [String]) -> String {
        "switch self {\n\(cases.joined(separator: "\n"))\n}"
    }
}
