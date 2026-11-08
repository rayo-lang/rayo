import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    var name: String
    /// The labels of the case's values, in order.
    var labels: [String]
    var number: Int
    var message: MessageTemplate
    var numberNode: ExprSyntax

    /// Reads `caseDecl`'s entry, or reports what keeps it from having one and returns nil.
    static func read(_ caseDecl: EnumCaseDeclSyntax, reporting errors: inout [Diagnostic]) -> CodeEntry? {
        guard let element = onlyElement(of: caseDecl, reporting: &errors),
              let code = onlyCode(on: caseDecl, named: element.name.text, reporting: &errors),
              let arguments = CodeArguments(code) else { return nil }

        let values = labeledValues(of: element, reporting: &errors)
        let number = number(in: arguments.number, reporting: &errors)
        let message = message(in: arguments.message, reporting: &errors)
        guard let values, let number, let message,
              placeholdersMatch(message, writtenAt: arguments.message, values: values, reporting: &errors) else {
            return nil
        }

        return CodeEntry(name: element.name.text, labels: values.map(\.label), number: number, message: message,
                         numberNode: arguments.number)
    }

    /// The pattern that matches the case and binds its values in order, as `v0`, `v1` and so on.
    var bindingPattern: String {
        labels.isEmpty ? ".\(name)" : ".\(name)(\(labels.indices.map { "let v\($0)" }.joined(separator: ", ")))"
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        "\"\(message.literalContent(valuesLabeled: labels))\""
    }

    // MARK: Steps of reading an entry

    /// The one case `caseDecl` declares, reporting a declaration of several.
    private static func onlyElement(of caseDecl: EnumCaseDeclSyntax,
                                    reporting errors: inout [Diagnostic]) -> EnumCaseElementSyntax? {
        guard caseDecl.elements.count == 1 else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.oneCasePerCode))
            return nil
        }
        return caseDecl.elements.first
    }

    /// The `@Code` on `caseDecl`, which declares the case `name`, reporting none, and any after the first.
    private static func onlyCode(on caseDecl: EnumCaseDeclSyntax, named name: String,
                                 reporting errors: inout [Diagnostic]) -> AttributeSyntax? {
        let codes = caseDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(isCode)
        guard let code = codes.first else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.caseWithoutCode(name)))
            return nil
        }
        errors += codes.dropFirst().map { Diagnostic(node: $0, message: CodeTableError.oneCodePerCase) }
        return code
    }

    /// `element`'s values with their labels, or nil after reporting each value without one.
    private static func labeledValues(of element: EnumCaseElementSyntax,
                                      reporting errors: inout [Diagnostic]) -> [LabeledValue]? {
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        let unlabeled = parameters.filter { LabeledValue($0) == nil }
        errors += unlabeled.map { Diagnostic(node: $0, message: CodeTableError.unlabeledValue(element.name.text)) }
        return unlabeled.isEmpty ? parameters.compactMap(LabeledValue.init) : nil
    }

    /// The positive integer `expression` writes, reporting anything else.
    private static func number(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> Int? {
        if let value = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, value > 0 { return value }
        errors.append(Diagnostic(node: expression, message: CodeTableError.numberNotLiteral))
        return nil
    }

    /// The message `expression` writes, reporting one that isn't a plain string literal.
    private static func message(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> MessageTemplate? {
        if let message = MessageTemplate(expression) { return message }
        errors.append(Diagnostic(node: expression, message: CodeTableError.messageNotPlain))
        return nil
    }

    /// Whether `message` names each of `values` and nothing else, reporting a placeholder that names no
    /// value, and a value no placeholder names. A macro's error is placed at the start of a syntax node,
    /// so a placeholder's error is at the whole message, `expression`.
    private static func placeholdersMatch(_ message: MessageTemplate, writtenAt expression: ExprSyntax,
                                          values: [LabeledValue], reporting errors: inout [Diagnostic]) -> Bool {
        let named = message.placeholderLabels
        let unknown = named.filter { label in !values.contains { $0.label == label } }
        let unused = values.filter { !named.contains($0.label) }
        errors += unknown.map { Diagnostic(node: expression, message: CodeTableError.unknownPlaceholder($0)) }
        errors += unused.map { Diagnostic(node: $0.parameter, message: CodeTableError.unusedValue($0.label)) }
        return unknown.isEmpty && unused.isEmpty
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    private static func isCode(_ attribute: AttributeSyntax) -> Bool {
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
    }
}

/// A value of a case, and the label a message names it by.
private struct LabeledValue {
    var label: String
    var parameter: EnumCaseParameterSyntax

    /// Nil when `parameter` has no label, or `_`.
    init?(_ parameter: EnumCaseParameterSyntax) {
        guard let label = parameter.firstName, label.tokenKind != .wildcard else { return nil }
        self.label = label.identifier?.name ?? label.text
        self.parameter = parameter
    }
}

/// The two arguments of a `@Code`.
private struct CodeArguments {
    var number: ExprSyntax
    var message: ExprSyntax

    /// Nil when the arguments don't fit `@Code`, which the compiler reports.
    init?(_ code: AttributeSyntax) {
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let number = arguments.first, let message = arguments.last else { return nil }
        self.number = number.expression
        self.message = message.expression
    }
}
