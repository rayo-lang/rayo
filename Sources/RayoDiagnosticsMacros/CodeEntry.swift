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
        // A case without values matches by its name alone.
        guard !labels.isEmpty else { return ".\(name)" }
        let bindings = labels.indices.map { "let v\($0)" }
        return ".\(name)(\(bindings.joined(separator: ", ")))"
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        "\"\(message.literalContent(valuesLabeled: labels))\""
    }

    // MARK: Steps of reading an entry

    /// The one case `caseDecl` declares, reporting a declaration of several.
    private static func onlyElement(of caseDecl: EnumCaseDeclSyntax,
                                    reporting errors: inout [Diagnostic]) -> EnumCaseElementSyntax? {
        // A declaration of several cases is reported, since each case needs a code of its own.
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
        // A case without a `@Code` is reported.
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
        // A value without a label, which a message couldn't name, leaves the case without values.
        guard unlabeled.isEmpty else { return nil }
        return parameters.compactMap(LabeledValue.init)
    }

    /// The positive integer `expression` writes, reporting anything else.
    private static func number(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> Int? {
        // A positive integer literal is the number.
        if let value = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, value > 0 { return value }
        errors.append(Diagnostic(node: expression, message: CodeTableError.numberNotLiteral))
        return nil
    }

    /// The message `expression` writes, reporting one that isn't a plain string literal.
    private static func message(in expression: ExprSyntax, reporting errors: inout [Diagnostic]) -> MessageTemplate? {
        // A plain string literal is the message.
        if let message = MessageTemplate(expression) { return message }
        errors.append(Diagnostic(node: expression, message: CodeTableError.messageNotPlain))
        return nil
    }

    /// Whether `message` names each of `values` and nothing else, reporting a placeholder that names no
    /// value, and a value no placeholder names.
    private static func placeholdersMatch(_ message: MessageTemplate, writtenAt expression: ExprSyntax,
                                          values: [LabeledValue], reporting errors: inout [Diagnostic]) -> Bool {
        let named = message.placeholderLabels
        let unknown = named.filter { label in !values.contains { $0.label == label } }
        let unused = values.filter { !named.contains($0.label) }
        // A macro's error lies at the start of a syntax node, so a placeholder's error covers the whole message.
        errors += unknown.map { Diagnostic(node: expression, message: CodeTableError.unknownPlaceholder($0)) }
        errors += unused.map { Diagnostic(node: $0.parameter, message: CodeTableError.unusedValue($0.label)) }
        return unknown.isEmpty && unused.isEmpty
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    private static func isCode(_ attribute: AttributeSyntax) -> Bool {
        // A name written alone is the attribute's own,
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        // and one written after its module's name is the member's.
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
    }
}

/// A value of a case, and the label a message names it by.
private struct LabeledValue {
    var label: String
    var parameter: EnumCaseParameterSyntax

    /// Nil when `parameter` has no label, or `_`.
    init?(_ parameter: EnumCaseParameterSyntax) {
        // A message names a value only by its label.
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
        // Arguments other than a number and a message are the compiler's to report.
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let number = arguments.first, let message = arguments.last else { return nil }
        self.number = number.expression
        self.message = message.expression
    }
}

/// A code's message as `@Code` gives it: text, and `{label}` placeholders for the case's values.
struct MessageTemplate {
    enum Part {
        /// Text as written in the source, escapes included.
        case text(String)
        case value(label: String)
    }

    var parts: [Part]

    /// The template `expression` holds, or nil when it isn't a one-line string literal without
    /// interpolation. Only `{name}` is a placeholder, so other braces, and `\u{…}`, are text.
    init?(_ expression: ExprSyntax) {
        // A message that isn't a plain literal has no template.
        guard let source = Self.plainSource(of: expression) else { return nil }
        parts = Self.parts(of: Array(source.unicodeScalars))
    }

    /// The labels the placeholders name, each once, in the order they first appear.
    var placeholderLabels: [String] {
        var labels: [String] = []
        for case .value(let label) in parts where !labels.contains(label) {
            labels.append(label)
        }
        return labels
    }

    /// The message as the inside of a Swift string literal, in which the value labeled `labels[i]` is `v<i>`.
    /// Every placeholder names one of `labels`.
    func literalContent(valuesLabeled labels: [String]) -> String {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .value(let label): "\\(v\(labels.firstIndex(of: label)!))"
            }
        }.joined()
    }

    /// The source text inside `expression`, when it is a one-line string literal without interpolation.
    private static func plainSource(of expression: ExprSyntax) -> String? {
        // Only a one-line literal without `#` delimiters is plain.
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.openingPounds == nil,
              literal.openingQuote.tokenKind == .stringQuote else { return nil }

        // Join the literal's text, which an interpolated segment makes not plain.
        var source = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            source += plain.content.text
        }
        return source
    }

    /// Splits `scalars` into text and placeholders.
    private static func parts(of scalars: [Unicode.Scalar]) -> [Part] {
        var parts: [Part] = []
        var text = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            // A placeholder ends the text before it, and the scan goes on after its `}`.
            if let placeholder = placeholder(in: scalars, at: index) {
                parts += [.text(String(text)), .value(label: placeholder.label)]
                text = String.UnicodeScalarView()
                index = placeholder.end
            } else {
                // Any other scalar is text.
                text.append(scalars[index])
                index += 1
            }
        }
        return parts + [.text(String(text))]
    }

    /// The `{identifier}` that starts at `start`: the identifier, and the index just past the `}`.
    private static func placeholder(in scalars: [Unicode.Scalar], at start: Int) -> (label: String, end: Int)? {
        // A brace that opens a `\u{…}` escape, or that an identifier and a `}` don't follow, is text.
        guard scalars[start] == "{", !isUnicodeEscape(scalars, braceAt: start),
              let labelEnd = identifierEnd(in: scalars, from: start + 1), labelEnd < scalars.count,
              scalars[labelEnd] == "}" else { return nil }
        let label = String(String.UnicodeScalarView(scalars[(start + 1)..<labelEnd]))
        return (label, labelEnd + 1)
    }

    /// Whether the brace at `brace` opens a `\u{…}` escape.
    private static func isUnicodeEscape(_ scalars: [Unicode.Scalar], braceAt brace: Int) -> Bool {
        // A brace that doesn't follow a `\u` opens no escape.
        guard brace >= 2, scalars[brace - 1] == "u" else { return false }

        // The `u` escapes only after an odd run of backslashes, since an even run is that many escaped backslashes.
        var backslashes = 0
        while brace - 2 - backslashes >= 0, scalars[brace - 2 - backslashes] == "\\" { backslashes += 1 }
        return backslashes % 2 == 1
    }

    /// The index just past the Swift identifier that starts at `start`, or nil when none starts there.
    private static func identifierEnd(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        // Nothing starts there that can't start an identifier.
        guard start < scalars.count, scalars[start] == "_" || scalars[start].properties.isXIDStart else { return nil }
        var end = start + 1
        while end < scalars.count, scalars[end].properties.isXIDContinue { end += 1 }
        return end
    }
}
