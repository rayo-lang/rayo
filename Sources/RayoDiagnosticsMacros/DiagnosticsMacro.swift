import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Diagnostics`, which gives an enum of codes a `number`, a `message`, a `severity` and `labels` made from each
/// case's `@Code`, and a `Label` enum with a case for each label any code declares.
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

    private static var members: [Member] {
        [
            Member(name: "number", type: "Int", fallbackBody: "0") { entries in
                switchOverSelf(entries.map { "case .\($0.name): \($0.number)" })
            },
            Member(name: "message", type: "String", fallbackBody: "\"\"") { entries in
                switchOverSelf(entries.map { "case \($0.bindingPattern): \($0.messageLiteral)" })
            },
            Member(name: "severity", type: "Severity", fallbackBody: ".error") { entries in
                switchOverSelf(entries.map { "case .\($0.name): .\($0.severity)" })
            },
            Member(name: "labels", type: "[Label: String]", fallbackBody: "[:]", body: labelsBody),
        ]
    }

    /// The body of `labels`: each code's labels, and none for a code that declares none.
    private static func labelsBody(_ entries: [CodeEntry]) -> String {
        let labeled = entries.filter { !$0.labels.isEmpty }
        if labeled.isEmpty { return "[:]" }
        let cases = labeled.map { "case \($0.labelsBindingPattern): \($0.labelsLiteral)" }
        return switchOverSelf(labeled.count == entries.count ? cases : cases + ["default: [:]"])
    }

    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax,
                                 conformingTo protocols: [TypeSyntax],
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.notAnEnum))
            return []
        }
        var errors: [Diagnostic] = []
        let generated = membersToGenerate(in: enumDecl, reporting: &errors)
        let generatesLabel = labelTypeIsFree(in: enumDecl, reporting: &errors)
        errors += conditionalCases(in: enumDecl)
        let entries = entries(of: enumDecl, reporting: &errors)
        errors.forEach { context.diagnose($0) }

        // Only a table read whole and without errors gets the members' bodies; `Label` takes what was read.
        let access = accessModifier(of: enumDecl)
        let readEntries = entries.compactMap(\.self)
        let wholeTable = errors.isEmpty && readEntries.count == entries.count ? readEntries : nil
        let members = generated.map { $0.declaration(for: wholeTable, access: access) }
        guard generatesLabel else { return members }
        return members + [labelType(declaredBy: readEntries, access: access)]
    }

    /// The `Label` enum, with a case for each label `entries` declare, in the order they first declare them. A table
    /// written wrong gets the labels of the entries read without errors, so that its uses of them still compile.
    private static func labelType(declaredBy entries: [CodeEntry], access: String) -> DeclSyntax {
        var names: [String] = []
        for label in entries.flatMap(\.labels) where !names.contains(label.name) {
            names.append(label.name)
        }
        let cases = names.map { "case \($0)\n" }.joined()
        return "\(raw: access)enum Label: Sendable, Hashable {\n\(raw: cases)}"
    }

    /// Whether `enumDecl` leaves the name `Label` free for the generated enum, reporting a type it declares by
    /// that name.
    private static func labelTypeIsFree(in enumDecl: EnumDeclSyntax, reporting errors: inout [Diagnostic]) -> Bool {
        let declaration = enumDecl.memberBlock.members.first { member in
            let isType = member.decl.is(StructDeclSyntax.self) || member.decl.is(EnumDeclSyntax.self)
                || member.decl.is(ClassDeclSyntax.self) || member.decl.is(TypeAliasDeclSyntax.self)
            return isType && member.decl.asProtocol(NamedDeclSyntax.self)?.name.text == "Label"
        }
        guard let declaration else { return true }
        errors.append(Diagnostic(node: declaration.decl, message: CodeTableError.memberTaken("Label")))
        return false
    }

    /// The members the macro generates that `enumDecl` doesn't declare itself, reporting each it does.
    private static func membersToGenerate(in enumDecl: EnumDeclSyntax, reporting errors: inout [Diagnostic]) -> [Member] {
        members.filter { member in
            guard let declaration = instanceDeclaration(named: member.name, in: enumDecl) else { return true }
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

    /// Each case's entry, in order, nil for a case that has none. Reports a number used twice.
    private static func entries(of enumDecl: EnumDeclSyntax, reporting errors: inout [Diagnostic]) -> [CodeEntry?] {
        let cases = enumDecl.memberBlock.members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        let entries = cases.map { CodeEntry.read($0, reporting: &errors) }
        errors += duplicateNumbers(in: entries.compactMap(\.self))
        return entries
    }

    /// An error at each entry whose number an earlier entry has, with a note at that earlier one.
    private static func duplicateNumbers(in entries: [CodeEntry]) -> [Diagnostic] {
        var firstUses: [Int: ExprSyntax] = [:]
        return entries.compactMap { entry in
            guard let firstUse = firstUses[entry.number] else {
                firstUses[entry.number] = entry.numberNode
                return nil
            }
            let note = Note(node: Syntax(firstUse), message: CodeTableNote.firstUse(entry.number))
            return Diagnostic(node: entry.numberNode, message: CodeTableError.duplicateNumber(entry.number), notes: [note])
        }
    }

    /// The cases declared under an `#if` among `members`, at any depth.
    private static func casesUnderIf(in members: MemberBlockItemListSyntax) -> [EnumCaseDeclSyntax] {
        members.flatMap { member -> [EnumCaseDeclSyntax] in
            guard let conditional = member.decl.as(IfConfigDeclSyntax.self) else { return [] }
            return conditional.clauses.flatMap { clause -> [EnumCaseDeclSyntax] in
                guard case .decls(let clauseMembers) = clause.elements else { return [] }
                return clauseMembers.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) } + casesUnderIf(in: clauseMembers)
            }
        }
    }

    /// The instance property or method of `enumDecl` named `name`, if there is one.
    private static func instanceDeclaration(named name: String, in enumDecl: EnumDeclSyntax) -> DeclSyntax? {
        enumDecl.memberBlock.members.first { member in
            if let variable = member.decl.as(VariableDeclSyntax.self), !isStatic(variable.modifiers) {
                return variable.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name }
            }
            if let function = member.decl.as(FunctionDeclSyntax.self), !isStatic(function.modifiers) {
                return function.name.text == name
            }
            return false
        }?.decl
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    /// `public ` or `package ` when the enum is, so that its generated members are too; otherwise nothing.
    private static func accessModifier(of enumDecl: EnumDeclSyntax) -> String {
        enumDecl.modifiers.first { ["public", "package"].contains($0.name.text) }.map { "\($0.name.text) " } ?? ""
    }

    private static func switchOverSelf(_ cases: [String]) -> String {
        "switch self {\n\(cases.joined(separator: "\n"))\n}"
    }
}
