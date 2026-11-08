import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    var name: String
    /// The labels of the case's values, in order.
    var labels: [String]
    var number: Int
    var message: MessageTemplate
    var isNotSupported: Bool
    var numberNode: ExprSyntax

    /// Reads `caseDecl`'s entry, or reports what keeps it from having one and returns nil.
    static func read(_ caseDecl: EnumCaseDeclSyntax, reporting errors: inout [Diagnostic]) -> CodeEntry? {
        guard let element = onlyElement(of: caseDecl, reporting: &errors),
              let code = onlyCode(on: caseDecl, reporting: &errors),
              let arguments = CodeArguments(code) else { return nil }

        let errorsBefore = errors.count
        let labels = labels(of: element, reporting: &errors)
        let number = number(in: arguments.number, reporting: &errors)
        let message = message(in: arguments.message, for: element, reporting: &errors)
        guard let number, let message, errors.count == errorsBefore else { return nil }

        return CodeEntry(name: element.name.text, labels: labels, number: number, message: message,
                         isNotSupported: arguments.isNotSupported, numberNode: arguments.number)
    }

    /// The pattern that matches the case and binds its values in order, as `v0`, `v1` and so on.
    var bindingPattern: String {
        labels.isEmpty ? ".\(name)" : ".\(name)(\(labels.indices.map { "let v\($0)" }.joined(separator: ", ")))"
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        message.literal(valuesLabeled: labels, isNotSupported: isNotSupported)
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    static func isCode(_ attribute: AttributeSyntax) -> Bool {
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
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

    /// The `@Code` on `caseDecl`, reporting none, and any after the first.
    private static func onlyCode(on caseDecl: EnumCaseDeclSyntax, reporting errors: inout [Diagnostic]) -> AttributeSyntax? {
        let codes = caseDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(isCode)
        guard let code = codes.first else {
            let name = caseDecl.elements.first?.name.text ?? ""
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.caseWithoutCode(name)))
            return nil
        }
        errors += codes.dropFirst().map { Diagnostic(node: $0, message: CodeTableError.oneCodePerCase) }
        return code
    }

    /// The labels of `element`'s values, reporting each value without one.
    private static func labels(of element: EnumCaseElementSyntax, reporting errors: inout [Diagnostic]) -> [String] {
        (element.parameterClause?.parameters ?? []).compactMap { parameter in
            if let label = label(of: parameter) { return label }
            errors.append(Diagnostic(node: parameter, message: CodeTableError.unlabeledValue(element.name.text)))
            return nil
        }
    }

    /// The positive integer `expression` writes, reporting anything else.
    private static func number(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> Int? {
        if let value = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, value > 0 { return value }
        errors.append(Diagnostic(node: expression, message: CodeTableError.numberNotLiteral))
        return nil
    }

    /// The message `expression` writes for `element`, reporting one that isn't a plain literal, a
    /// placeholder that names no value, and a value no placeholder names. The compiler can place an error
    /// at a token at best, so a placeholder's error is at the whole message.
    private static func message(in expression: ExprSyntax, for element: EnumCaseElementSyntax,
                                reporting errors: inout [Diagnostic]) -> MessageTemplate? {
        guard let message = MessageTemplate(expression) else {
            errors.append(Diagnostic(node: expression, message: CodeTableError.messageNotPlain))
            return nil
        }
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        let labels = parameters.compactMap(label(of:))
        let named = message.placeholderLabels
        for unknown in named where !labels.contains(unknown) {
            errors.append(Diagnostic(node: expression, message: CodeTableError.unknownPlaceholder(unknown)))
        }
        for parameter in parameters {
            guard let label = label(of: parameter), let token = parameter.firstName, !named.contains(label) else { continue }
            errors.append(Diagnostic(node: token, message: CodeTableError.unusedValue(label)))
        }
        return message
    }

    /// The label a message names `parameter` by, or nil when it has none.
    private static func label(of parameter: EnumCaseParameterSyntax) -> String? {
        guard let label = parameter.firstName, label.tokenKind != .wildcard else { return nil }
        return label.identifier?.name ?? label.text
    }
}

/// The two arguments of a `@Code`.
private struct CodeArguments {
    var number: ExprSyntax
    var message: ExprSyntax
    /// True for `notSupported:`, false for `error:`.
    var isNotSupported: Bool

    /// Nil when the arguments fit neither `@Code`, which the compiler reports.
    init?(_ code: AttributeSyntax) {
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let number = arguments.first, let message = arguments.last else { return nil }
        self.number = number.expression
        self.message = message.expression
        isNotSupported = message.label?.text == "notSupported"
    }
}
