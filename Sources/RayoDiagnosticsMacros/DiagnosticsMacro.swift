import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Diagnostics`, which gives an enum of codes a `number` and a `message` made from each case's `@Code`.
/// A table written wrong gets errors where it is wrong, and members that keep its uses compiling, so that
/// only those errors are reported.
public struct DiagnosticsMacro: MemberMacro {
    /// A member the macro generates: a property with a body for a table that reads, and one that keeps a
    /// table written wrong compiling.
    private struct Member {
        var name: String
        var type: String
        var placeholder: String
        var body: ([CodeEntry]) -> String
    }

    private static var members: [Member] {
        [
            Member(name: "number", type: "Int", placeholder: "0") { entries in
                switchOverSelf(entries.map { "case .\($0.name): \($0.number)" })
            },
            Member(name: "message", type: "String", placeholder: "\"\"") { entries in
                switchOverSelf(entries.map { "case \($0.bindingPattern): \($0.messageLiteral)" })
            },
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.notAnEnum))
            return []
        }
        let taken = takenNames(in: enumDecl)
        var errors = taken.map { Diagnostic(node: $0.declaration, message: CodeTableError.memberTaken($0.name)) }
        let entries = entries(of: enumDecl, reporting: &errors)
        errors.forEach { context.diagnose($0) }

        let access = enumDecl.modifiers.first { ["public", "package"].contains($0.name.text) }
            .map { "\($0.name.text) " } ?? ""
        let readEntries = errors.isEmpty ? entries : nil
        return members.filter { member in !taken.contains { $0.name == member.name } }.map { member in
            """
            \(raw: access)var \(raw: member.name): \(raw: member.type) {
                \(raw: readEntries.map(member.body) ?? member.placeholder)
            }
            """
        }
    }

    /// Each case's entry, in order, or nil when any case has none. Reports a number used twice, and a
    /// case under `#if`.
    private static func entries(of enumDecl: EnumDeclSyntax, reporting errors: inout [Diagnostic]) -> [CodeEntry]? {
        var entries: [CodeEntry] = []
        var allRead = true
        var firstUses: [Int: ExprSyntax] = [:]
        for member in enumDecl.memberBlock.members {
            if let conditional = member.decl.as(IfConfigDeclSyntax.self) {
                errors += casesUnder(conditional).map { Diagnostic(node: $0.caseKeyword, message: CodeTableError.conditionalCase) }
                continue
            }
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            guard let entry = CodeEntry.read(caseDecl, reporting: &errors) else {
                allRead = false
                continue
            }
            if let firstUse = firstUses[entry.number] {
                let note = Note(node: Syntax(firstUse), message: CodeTableNote.firstUse(entry.number))
                errors.append(Diagnostic(node: entry.numberNode, message: CodeTableError.duplicateNumber(entry.number),
                                         notes: [note]))
            } else {
                firstUses[entry.number] = entry.numberNode
            }
            entries.append(entry)
        }
        return allRead ? entries : nil
    }

    /// The cases declared under `conditional`, in any of its clauses.
    private static func casesUnder(_ conditional: IfConfigDeclSyntax) -> [EnumCaseDeclSyntax] {
        conditional.clauses.flatMap { clause -> [EnumCaseDeclSyntax] in
            guard case .decls(let members) = clause.elements else { return [] }
            return members.flatMap { member -> [EnumCaseDeclSyntax] in
                if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) { return [caseDecl] }
                return member.decl.as(IfConfigDeclSyntax.self).map(casesUnder) ?? []
            }
        }
    }

    /// The instance members of `enumDecl` that declare a name the macro generates.
    private static func takenNames(in enumDecl: EnumDeclSyntax) -> [(name: String, declaration: DeclSyntax)] {
        enumDecl.memberBlock.members.compactMap { member in
            let declared: [String]
            if let variable = member.decl.as(VariableDeclSyntax.self), !isStatic(variable.modifiers) {
                declared = variable.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
            } else if let function = member.decl.as(FunctionDeclSyntax.self), !isStatic(function.modifiers) {
                declared = [function.name.text]
            } else {
                declared = []
            }
            return declared.first { name in members.contains { $0.name == name } }.map { ($0, member.decl) }
        }
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    private static func switchOverSelf(_ cases: [String]) -> String {
        "switch self {\n\(cases.joined(separator: "\n"))\n}"
    }
}
