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
        // A case without values is matched by its name alone.
        guard !labels.isEmpty else { return ".\(name)" }

        // Bind the values in order, each to `v` and its index.
        let bindings = labels.indices.map { "let v\($0)" }.joined(separator: ", ")
        return ".\(name)(\(bindings))"
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        "\"\(message.literalContent(valuesLabeled: labels))\""
    }

    // MARK: Steps of reading an entry

    /// The one case `caseDecl` declares, reporting a declaration of several.
    private static func onlyElement(of caseDecl: EnumCaseDeclSyntax,
                                    reporting errors: inout [Diagnostic]) -> EnumCaseElementSyntax? {
        // A `@Code` before `case a, b` can't say which of them it numbers.
        guard caseDecl.elements.count == 1 else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.oneCasePerCode))
            return nil
        }

        return caseDecl.elements.first
    }

    /// The first `@Code` on `caseDecl`, which declares the case `name`. Reports a case without one, and each one
    /// after the first.
    private static func onlyCode(on caseDecl: EnumCaseDeclSyntax, named name: String,
                                 reporting errors: inout [Diagnostic]) -> AttributeSyntax? {
        let codes = caseDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(isCode)

        // A case without a `@Code` has nothing to read.
        guard let code = codes.first else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.caseWithoutCode(name)))
            return nil
        }

        // Report each `@Code` after the first, and read the first.
        errors += codes.dropFirst().map { Diagnostic(node: $0, message: CodeTableError.oneCodePerCase) }
        return code
    }

    /// `element`'s values with their labels, or nil after reporting each value without one.
    private static func labeledValues(of element: EnumCaseElementSyntax,
                                      reporting errors: inout [Diagnostic]) -> [LabeledValue]? {
        // Report every value without a label, so that one expansion shows them all.
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        let unlabeled = parameters.filter { LabeledValue($0) == nil }
        errors += unlabeled.map { Diagnostic(node: $0, message: CodeTableError.unlabeledValue(element.name.text)) }

        // A value without a label can't be named by the message, so the case has no entry.
        guard unlabeled.isEmpty else { return nil }

        return parameters.compactMap(LabeledValue.init)
    }

    /// The positive integer `expression` writes, reporting anything else.
    private static func number(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> Int? {
        // A positive integer literal is the number.
        if let value = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, value > 0 { return value }

        // Anything else, a constant's name or a negative number among them, is no number the macro can read.
        errors.append(Diagnostic(node: expression, message: CodeTableError.numberNotLiteral))
        return nil
    }

    /// The message `expression` writes, reporting one that isn't a plain string literal.
    private static func message(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> MessageTemplate? {
        // A plain string literal is the message.
        if let message = MessageTemplate(expression) { return message }

        // Anything else is no message the macro can read.
        errors.append(Diagnostic(node: expression, message: CodeTableError.messageNotPlain))
        return nil
    }

    /// Whether `message` names each of `values` and nothing else. Reports an error at `expression` for each
    /// placeholder that names no value, and an error at each value that no placeholder names.
    private static func placeholdersMatch(_ message: MessageTemplate, writtenAt expression: ExprSyntax,
                                          values: [LabeledValue], reporting errors: inout [Diagnostic]) -> Bool {
        // Find the placeholders that name no value, and the values that no placeholder names.
        let named = message.placeholderLabels
        let unknown = named.filter { label in !values.contains { $0.label == label } }
        let unused = values.filter { !named.contains($0.label) }

        // A macro's error goes at the start of a syntax node, so a placeholder's error goes at the whole message.
        errors += unknown.map { Diagnostic(node: expression, message: CodeTableError.unknownPlaceholder($0)) }
        errors += unused.map { Diagnostic(node: $0.parameter, message: CodeTableError.unusedValue($0.label)) }

        return unknown.isEmpty && unused.isEmpty
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    private static func isCode(_ attribute: AttributeSyntax) -> Bool {
        // `@Code` written alone.
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        // `@Code` after its module's name, as in `@RayoDiagnostics.Code`; any other attribute is no `@Code`.
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
    }
}

/// A value of a case, and the label a message names it by.
private struct LabeledValue {
    var label: String
    var parameter: EnumCaseParameterSyntax

    /// The value `parameter` declares, or nil when it has no label, or `_` for one.
    init?(_ parameter: EnumCaseParameterSyntax) {
        // A value without a label is one no message can name.
        guard let label = parameter.firstName, label.tokenKind != .wildcard else { return nil }

        // Name the value by its label, without the backticks it may have, and a keyword such as `in` by its text.
        self.label = label.identifier?.name ?? label.text
        self.parameter = parameter
    }
}

/// The two arguments of a `@Code`.
private struct CodeArguments {
    var number: ExprSyntax
    var message: ExprSyntax

    /// The arguments of `code`, or nil when they don't fit `@Code`, which the compiler reports.
    init?(_ code: AttributeSyntax) {
        // Arguments that don't fit `@Code` are left for the compiler to report.
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let number = arguments.first, let message = arguments.last else { return nil }

        // Keep the expressions that the two arguments write.
        self.number = number.expression
        self.message = message.expression
    }
}
