import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    /// A label the code declares for a place its diagnostic points to beside its own, and the label's text.
    struct Label {
        var name: String
        var text: MessageTemplate
    }

    var name: String
    /// The labels of the case's values, in order.
    var valueLabels: [String]
    var number: Int
    /// `error` or `warning`, as the `@Code` names the code's severity.
    var severity: String
    var message: MessageTemplate
    /// The code's labels, in the order the `@Code` writes them.
    var labels: [Label]
    var numberNode: ExprSyntax

    /// Reads `caseDecl`'s entry, or reports what keeps it from having one and returns nil.
    static func read(_ caseDecl: EnumCaseDeclSyntax, reporting errors: inout [Diagnostic]) -> CodeEntry? {
        guard let element = onlyElement(of: caseDecl, reporting: &errors),
              let code = onlyCode(on: caseDecl, named: element.name.text, reporting: &errors),
              let arguments = CodeArguments(code) else { return nil }

        let values = labeledValues(of: element, reporting: &errors)
        let number = number(in: arguments.number, reporting: &errors)
        let message = message(in: arguments.message, reporting: &errors)
        let labels = labels(in: arguments.labels, reporting: &errors)
        guard let values, let number, let message, let labels else { return nil }

        // Every placeholder is checked, the message's and the labels', so that each wrong one is reported.
        let messageMatches = placeholdersMatch(message, writtenAt: arguments.message, values: values,
                                               reporting: &errors)
        let labelsMatch = labelPlaceholdersKnown(labels, values: values, reporting: &errors)
        guard messageMatches && labelsMatch else { return nil }

        return CodeEntry(name: element.name.text, valueLabels: values.map(\.label), number: number,
                         severity: arguments.severity, message: message, labels: labels.map(\.label),
                         numberNode: arguments.number)
    }

    /// The pattern that matches the case and binds its values in order, as `v0`, `v1` and so on.
    var bindingPattern: String {
        bindingPattern(binding: valueLabels)
    }

    /// The pattern that matches the case and binds the values its labels' texts name, each as `v<i>` for its
    /// position, and skips the rest, so that no binding goes unused.
    var labelsBindingPattern: String {
        bindingPattern(binding: labels.flatMap(\.text.placeholderLabels))
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        "\"\(message.literalContent(valuesLabeled: valueLabels))\""
    }

    /// The labels as a Swift dictionary literal, from each label's kind to its text, which interpolates the values
    /// `labelsBindingPattern` binds.
    var labelsLiteral: String {
        let pairs = labels.map { ".\($0.name): \"\($0.text.literalContent(valuesLabeled: valueLabels))\"" }
        return "[\(pairs.joined(separator: ", "))]"
    }

    /// The pattern that matches the case, binding each value `bound` names as `v<i>` and skipping the others.
    private func bindingPattern(binding bound: [String]) -> String {
        guard valueLabels.contains(where: bound.contains) else { return ".\(name)" }
        let values = valueLabels.indices.map { bound.contains(valueLabels[$0]) ? "let v\($0)" : "_" }
        return ".\(name)(\(values.joined(separator: ", ")))"
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

    /// The labels `expression` declares, each with the text's syntax, or none when there is no expression. Reports an
    /// expression that isn't a dictionary literal, and each label whose name isn't an identifier, whose text isn't
    /// plain, or whose name an earlier label has.
    private static func labels(in expression: ExprSyntax?,
                               reporting errors: inout [Diagnostic]) -> [(label: Label, textNode: ExprSyntax)]? {
        guard let expression else { return [] }
        guard let dictionary = expression.as(DictionaryExprSyntax.self) else {
            errors.append(Diagnostic(node: expression, message: CodeTableError.labelsNotLiteral))
            return nil
        }
        // `[:]` declares no labels.
        guard case .elements(let elements) = dictionary.content else { return [] }

        var labels: [(label: Label, textNode: ExprSyntax)] = []
        var wellWritten = true
        for element in elements {
            guard let label = label(in: element, reporting: &errors) else {
                wellWritten = false
                continue
            }
            if labels.contains(where: { $0.label.name == label.name }) {
                errors.append(Diagnostic(node: element.key, message: CodeTableError.labelTwice(label.name)))
                wellWritten = false
            }
            labels.append((label, element.value))
        }
        return wellWritten ? labels : nil
    }

    /// The label `element` declares, reporting a name that isn't an identifier and a text that isn't plain.
    private static func label(in element: DictionaryElementSyntax, reporting errors: inout [Diagnostic]) -> Label? {
        let name = MessageTemplate(element.key)?.plainText.flatMap { isIdentifier($0) ? $0 : nil }
        if name == nil { errors.append(Diagnostic(node: element.key, message: CodeTableError.labelNameNotIdentifier)) }
        let text = MessageTemplate(element.value)
        if text == nil { errors.append(Diagnostic(node: element.value, message: CodeTableError.labelNotPlain)) }

        guard let name, let text else { return nil }
        return Label(name: name, text: text)
    }

    /// Whether each label's text names only `values`, reporting each placeholder that names no value at the text.
    /// A label needn't name every value, since the message already does.
    private static func labelPlaceholdersKnown(_ labels: [(label: Label, textNode: ExprSyntax)], values: [LabeledValue],
                                               reporting errors: inout [Diagnostic]) -> Bool {
        var known = true
        for (label, textNode) in labels {
            for name in label.text.placeholderLabels where !values.contains(where: { $0.label == name }) {
                errors.append(Diagnostic(node: textNode, message: CodeTableError.unknownPlaceholder(name)))
                known = false
            }
        }
        return known
    }

    /// Whether `text` is a Swift identifier, which a label's name has to be, since it names a case of the
    /// generated `Label`.
    private static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, first == "_" || first.properties.isXIDStart else { return false }
        return text.unicodeScalars.dropFirst().allSatisfy(\.properties.isXIDContinue)
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

/// The arguments of a `@Code`: its number, its message under the label that names its severity, and its labels
/// where it has any.
private struct CodeArguments {
    var number: ExprSyntax
    var severity: String
    var message: ExprSyntax
    var labels: ExprSyntax?

    /// Nil when the arguments don't fit `@Code`, which the compiler reports.
    init?(_ code: AttributeSyntax) {
        guard case .argumentList(let list) = code.arguments, (2...3).contains(list.count) else { return nil }
        let arguments = Array(list)
        guard let severity = arguments[1].label?.text, severity == "error" || severity == "warning" else { return nil }
        let labels = arguments.count == 3 ? arguments[2] : nil
        guard labels == nil || labels?.label?.text == "labels" else { return nil }

        number = arguments[0].expression
        self.severity = severity
        message = arguments[1].expression
        self.labels = labels?.expression
    }
}
