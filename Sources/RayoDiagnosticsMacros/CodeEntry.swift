import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    /// A piece of a message: text as written in the source, or the label a placeholder names.
    enum Part {
        case text(String)
        case value(label: String)
    }

    var name: String
    /// The labels of the case's values, in order.
    var labels: [String]
    var number: Int
    var message: [Part]
    var isNotSupported: Bool
    var numberNode: ExprSyntax

    /// Reads `caseDecl`'s entry, or reports what keeps it from having one and returns nil.
    static func read(_ caseDecl: EnumCaseDeclSyntax, reporting errors: inout [Diagnostic]) -> CodeEntry? {
        guard caseDecl.elements.count == 1, let element = caseDecl.elements.first else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.oneCasePerCode))
            return nil
        }
        let codes = caseDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(isCode)
        guard let code = codes.first else {
            errors.append(Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.caseWithoutCode(element.name.text)))
            return nil
        }
        // The compiler reports an argument list that fits neither '@Code'.
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let numberArgument = arguments.first, let messageArgument = arguments.last else { return nil }

        let errorCount = errors.count
        errors += codes.dropFirst().map { Diagnostic(node: $0, message: CodeTableError.oneCodePerCase) }
        let labels = readLabels(of: element, reporting: &errors)
        let number = positiveInteger(numberArgument.expression)
        if number == nil {
            errors.append(Diagnostic(node: numberArgument.expression, message: CodeTableError.numberNotLiteral))
        }
        let message = parts(of: messageArgument.expression)
        if let message {
            errors += placeholderErrors(message, in: element, literal: messageArgument.expression)
        } else {
            errors.append(Diagnostic(node: messageArgument.expression, message: CodeTableError.messageNotPlain))
        }
        guard let number, let message, errors.count == errorCount else { return nil }
        return CodeEntry(name: element.name.text, labels: labels, number: number, message: message,
                         isNotSupported: messageArgument.label?.text == "notSupported",
                         numberNode: numberArgument.expression)
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    static func isCode(_ attribute: AttributeSyntax) -> Bool {
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
    }

    /// The label of `parameter`, which a message names it by, or nil when it has none.
    private static func label(of parameter: EnumCaseParameterSyntax) -> String? {
        guard let label = parameter.firstName, label.tokenKind != .wildcard else { return nil }
        return label.identifier?.name ?? label.text
    }

    /// The labels of `element`'s values, reporting each value without one.
    private static func readLabels(of element: EnumCaseElementSyntax, reporting errors: inout [Diagnostic]) -> [String] {
        (element.parameterClause?.parameters ?? []).compactMap { parameter in
            if let label = label(of: parameter) { return label }
            errors.append(Diagnostic(node: parameter, message: CodeTableError.unlabeledValue(element.name.text)))
            return nil
        }
    }

    private static func positiveInteger(_ expression: ExprSyntax) -> Int? {
        guard let value = expression.as(IntegerLiteralExprSyntax.self)?.representedLiteralValue, value > 0 else {
            return nil
        }
        return value
    }

    /// The pieces of the message `expression` holds, when it is a one-line string literal without
    /// interpolation. Only `{name}` is a placeholder, so other braces, and `\u{…}`, are text.
    private static func parts(of expression: ExprSyntax) -> [Part]? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.openingPounds == nil,
              literal.openingQuote.tokenKind == .stringQuote else { return nil }
        var source = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            source += plain.content.text
        }
        let bytes = Array(source.utf8)
        var parts: [Part] = []
        var text: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "{"), !isUnicodeEscape(bytes, braceAt: index),
               let end = identifierEnd(in: bytes, from: index + 1), end < bytes.count, bytes[end] == UInt8(ascii: "}") {
                parts.append(.text(String(decoding: text, as: UTF8.self)))
                parts.append(.value(label: String(decoding: bytes[(index + 1)..<end], as: UTF8.self)))
                text = []
                index = end + 1
            } else {
                text.append(bytes[index])
                index += 1
            }
        }
        parts.append(.text(String(decoding: text, as: UTF8.self)))
        return parts
    }

    /// Whether the brace at `brace` opens a `\u{…}` escape: it follows a `u` after an odd run of
    /// backslashes, since an even run is that many escaped backslashes.
    private static func isUnicodeEscape(_ bytes: [UInt8], braceAt brace: Int) -> Bool {
        guard brace >= 2, bytes[brace - 1] == UInt8(ascii: "u") else { return false }
        var backslashes = 0
        while brace - 2 - backslashes >= 0, bytes[brace - 2 - backslashes] == UInt8(ascii: "\\") { backslashes += 1 }
        return backslashes % 2 == 1
    }

    /// The index just past the identifier that starts at `start`, or nil when none starts there. Any
    /// non-ASCII byte counts as a letter, as it may in a Swift identifier.
    private static func identifierEnd(in bytes: [UInt8], from start: Int) -> Int? {
        func isLetter(_ byte: UInt8) -> Bool {
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || byte == UInt8(ascii: "_") || byte >= 0x80
        }
        guard start < bytes.count, isLetter(bytes[start]) else { return nil }
        var end = start + 1
        while end < bytes.count, isLetter(bytes[end]) || (bytes[end] >= UInt8(ascii: "0") && bytes[end] <= UInt8(ascii: "9")) {
            end += 1
        }
        return end
    }

    /// The errors for placeholders that name no value, at the message, and for values that no
    /// placeholder names, at each value's label. The compiler places an error at a token at best, so it
    /// can't point inside the message.
    private static func placeholderErrors(_ message: [Part], in element: EnumCaseElementSyntax,
                                          literal: ExprSyntax) -> [Diagnostic] {
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        let labels = parameters.compactMap(label(of:))
        var errors: [Diagnostic] = []
        var named: [String] = []
        for case .value(let label) in message where !named.contains(label) {
            if !labels.contains(label) {
                errors.append(Diagnostic(node: literal, message: CodeTableError.unknownPlaceholder(label)))
            }
            named.append(label)
        }
        for parameter in parameters {
            guard let label = label(of: parameter), let token = parameter.firstName, !named.contains(label) else {
                continue
            }
            errors.append(Diagnostic(node: token, message: CodeTableError.unusedValue(label)))
        }
        return errors
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        let source = message.map { part in
            switch part {
            case .text(let text): text
            case .value(let label): "\\(v\(labels.firstIndex(of: label) ?? 0))"
            }
        }.joined()
        return "\"\(source)\(isNotSupported ? " isn't supported yet" : "")\""
    }

    /// The pattern that matches the case and binds its values in order, as `v0`, `v1` and so on.
    var bindingPattern: String {
        labels.isEmpty ? ".\(name)" : ".\(name)(\(labels.indices.map { "let v\($0)" }.joined(separator: ", ")))"
    }
}
