import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Diagnostics`, which gives an enum of codes a `number` and a `message` made from each case's `@Code`.
/// A table written wrong gets errors where it is wrong, and members that keep its uses compiling, so that
/// only those errors are reported.
public struct DiagnosticsMacro: MemberMacro {
    private static let generatedNames = ["number", "message"]

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
        let bodies: [String: String]
        if let entries, errors.isEmpty {
            bodies = [
                "number": switchOverSelf(entries.map { "case .\($0.name): \($0.number)" }),
                "message": switchOverSelf(entries.map { "case \($0.bindingPattern): \($0.messageLiteral)" }),
            ]
        } else {
            bodies = ["number": "0", "message": "\"\""]
        }
        let types = ["number": "Int", "message": "String"]
        return generatedNames.filter { name in !taken.contains { $0.name == name } }.map { name in
            """
            \(raw: access)var \(raw: name): \(raw: types[name]!) {
                \(raw: bodies[name]!)
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
            switch CodeEntry.read(caseDecl) {
            case .failure(let caseErrors):
                errors += caseErrors.list
                allRead = false
            case .success(let entry):
                if let firstUse = firstUses[entry.number] {
                    let note = Note(node: Syntax(firstUse), message: CodeTableNote.firstUse(entry.number))
                    errors.append(Diagnostic(node: entry.numberNode, message: CodeTableError.duplicateNumber(entry.number),
                                             notes: [note]))
                } else {
                    firstUses[entry.number] = entry.numberNode
                }
                entries.append(entry)
            }
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

    /// The members of `enumDecl` that declare a name the macro generates.
    private static func takenNames(in enumDecl: EnumDeclSyntax) -> [(name: String, declaration: DeclSyntax)] {
        enumDecl.memberBlock.members.compactMap { member in
            let declared: [String]
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                declared = variable.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                declared = [function.name.text]
            } else {
                declared = []
            }
            return declared.first(where: generatedNames.contains).map { ($0, member.decl) }
        }
    }

    private static func switchOverSelf(_ cases: [String]) -> String {
        "switch self {\n\(cases.joined(separator: "\n"))\n}"
    }
}
