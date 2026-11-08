import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Diagnostics`, which gives an enum of codes a `number` and a `message` made from each case's `@Code`.
/// A table written wrong gets errors where it is wrong, and no members.
public struct DiagnosticsMacro: MemberMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.notAnEnum))
            return []
        }
        switch entries(of: enumDecl) {
        case .failure(let errors):
            errors.list.forEach { context.diagnose($0) }
            return []
        case .success(let entries):
            let access = enumDecl.modifiers.first { ["public", "package"].contains($0.name.text) }
                .map { "\($0.name.text) " } ?? ""
            return [
                property("number", of: "Int", access: access, entries.map { "case .\($0.name): \($0.number)" }),
                property("message", of: "String", access: access,
                         entries.map { "case \($0.bindingPattern): \($0.messageLiteral)" }),
            ]
        }
    }

    /// Each case's entry, in order, or every error in the table.
    private static func entries(of enumDecl: EnumDeclSyntax) -> Result<[CodeEntry], Errors> {
        var entries: [CodeEntry] = []
        var errors: [Diagnostic] = []
        var numbers: Set<Int> = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            switch CodeEntry.read(caseDecl) {
            case .failure(let caseErrors):
                errors += caseErrors.list
            case .success(let entry):
                if !numbers.insert(entry.number).inserted {
                    errors.append(Diagnostic(node: entry.numberNode, message: CodeTableError.duplicateNumber(entry.number)))
                }
                errors += placeholderErrors(in: entry)
                entries.append(entry)
            }
        }
        return errors.isEmpty ? .success(entries) : .failure(Errors(errors))
    }

    /// The errors for placeholders that name no value, and for values that no placeholder names.
    private static func placeholderErrors(in entry: CodeEntry) -> [Diagnostic] {
        let placeholders = entry.placeholders
        var unknown: [String] = []
        for label in placeholders where !entry.labels.contains(label) && !unknown.contains(label) {
            unknown.append(label)
        }
        let unused = entry.labels.filter { !placeholders.contains($0) }
        return unknown.map { Diagnostic(node: entry.messageNode, message: CodeTableError.unknownPlaceholder($0)) }
            + unused.map { Diagnostic(node: entry.messageNode, message: CodeTableError.unusedValue($0)) }
    }

    private static func property(_ name: String, of type: String, access: String, _ cases: [String]) -> DeclSyntax {
        """
        \(raw: access)var \(raw: name): \(raw: type) {
            switch self {
            \(raw: cases.joined(separator: "\n"))
            }
        }
        """
    }
}
