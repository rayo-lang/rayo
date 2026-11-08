import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    /// A piece of a message: text as written in the source, or a placeholder.
    enum Part {
        case text(String)
        /// `{label}`, which starts `offset` UTF-8 bytes into the message's text.
        case value(label: String, offset: Int)
    }

    var name: String
    /// The labels of the case's values, in order.
    var labels: [String]
    var number: Int
    var message: [Part]
    var isNotSupported: Bool
    var numberNode: ExprSyntax

    /// Reads `caseDecl`'s entry, or returns the errors that keep it from having one.
    static func read(_ caseDecl: EnumCaseDeclSyntax) -> Result<CodeEntry, Errors> {
        guard caseDecl.elements.count == 1, let element = caseDecl.elements.first else {
            return .failure(Errors([Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.oneCasePerCode)]))
        }
        let codes = caseDecl.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter(isCode)
        guard let code = codes.first else {
            let error = CodeTableError.caseWithoutCode(element.name.text)
            return .failure(Errors([Diagnostic(node: caseDecl.caseKeyword, message: error)]))
        }
        // An argument list that fits neither '@Code' is reported by the compiler, which matches it to one.
        guard case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let numberArgument = arguments.first, let messageArgument = arguments.last else {
            return .failure(Errors([]))
        }
        var errors = codes.dropFirst().map { Diagnostic(node: $0, message: CodeTableError.oneCodePerCase) }
        let labels = readLabels(of: element, caseName: element.name.text, into: &errors)
        let number = positiveInteger(numberArgument.expression)
        if number == nil {
            errors.append(Diagnostic(node: numberArgument.expression, message: CodeTableError.numberNotLiteral))
        }
        let message = parts(of: messageArgument.expression)
        if let message {
            errors += placeholderErrors(message, labels: labels, in: element, literal: messageArgument.expression)
        } else {
            errors.append(Diagnostic(node: messageArgument.expression, message: CodeTableError.messageNotPlain))
        }
        guard let number, let message, errors.isEmpty else { return .failure(Errors(errors)) }
        return .success(CodeEntry(name: element.name.text, labels: labels, number: number, message: message,
                                  isNotSupported: messageArgument.label?.text == "notSupported",
                                  numberNode: numberArgument.expression))
    }

    /// Whether `attribute` is `@Code`, written alone or after its module's name.
    static func isCode(_ attribute: AttributeSyntax) -> Bool {
        if let name = attribute.attributeName.as(IdentifierTypeSyntax.self) { return name.name.text == "Code" }
        return attribute.attributeName.as(MemberTypeSyntax.self)?.name.text == "Code"
    }

    /// The labels of `element`'s values, reporting each value without one.
    private static func readLabels(of element: EnumCaseElementSyntax, caseName: String,
                                   into errors: inout [Diagnostic]) -> [String] {
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        return parameters.compactMap { parameter in
            guard let label = parameter.firstName, label.tokenKind != .wildcard else {
                errors.append(Diagnostic(node: parameter, message: CodeTableError.unlabeledValue(caseName)))
                return nil
            }
            return label.identifier?.name ?? label.text
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
            let isUnicodeEscape = index >= 2 && bytes[index - 2] == UInt8(ascii: "\\") && bytes[index - 1] == UInt8(ascii: "u")
            if bytes[index] == UInt8(ascii: "{"), !isUnicodeEscape, let end = identifierEnd(in: bytes, from: index + 1),
               end < bytes.count, bytes[end] == UInt8(ascii: "}") {
                parts.append(.text(String(decoding: text, as: UTF8.self)))
                parts.append(.value(label: String(decoding: bytes[(index + 1)..<end], as: UTF8.self), offset: index))
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

    /// The index just past the identifier that starts at `start`, or nil when none starts there.
    private static func identifierEnd(in bytes: [UInt8], from start: Int) -> Int? {
        func isLetter(_ byte: UInt8) -> Bool {
            (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
                || byte == UInt8(ascii: "_")
        }
        guard start < bytes.count, isLetter(bytes[start]) else { return nil }
        var end = start + 1
        while end < bytes.count, isLetter(bytes[end]) || (bytes[end] >= UInt8(ascii: "0") && bytes[end] <= UInt8(ascii: "9")) {
            end += 1
        }
        return end
    }

    /// The errors for placeholders that name no value, at each placeholder, and for values that no
    /// placeholder names, at each value's label.
    private static func placeholderErrors(_ message: [Part], labels: [String], in element: EnumCaseElementSyntax,
                                          literal: ExprSyntax) -> [Diagnostic] {
        let textStart = literal.as(StringLiteralExprSyntax.self)?.openingQuote.endPositionBeforeTrailingTrivia
        var errors: [Diagnostic] = []
        var named: Set<String> = []
        for case .value(let label, let offset) in message {
            if !labels.contains(label) && !named.contains(label) {
                let position = textStart.map { $0.advanced(by: offset) }
                errors.append(Diagnostic(node: literal, position: position, message: CodeTableError.unknownPlaceholder(label)))
            }
            named.insert(label)
        }
        for parameter in element.parameterClause?.parameters ?? [] {
            guard let label = parameter.firstName, let name = label.identifier?.name, !named.contains(name) else {
                continue
            }
            errors.append(Diagnostic(node: label, message: CodeTableError.unusedValue(name)))
        }
        return errors
    }

    /// The message as a Swift string literal that interpolates the values `bindingPattern` binds.
    var messageLiteral: String {
        let source = message.map { part in
            switch part {
            case .text(let text): text
            case .value(let label, _): "\\(v\(labels.firstIndex(of: label) ?? 0))"
            }
        }.joined()
        return "\"\(source)\(isNotSupported ? " isn't supported yet" : "")\""
    }

    /// The pattern that matches the case and binds its values in order, as `v0`, `v1` and so on.
    var bindingPattern: String {
        labels.isEmpty ? ".\(name)" : ".\(name)(\(labels.indices.map { "let v\($0)" }.joined(separator: ", ")))"
    }
}

/// Errors found while reading a `@Diagnostics` enum.
struct Errors: Error {
    var list: [Diagnostic]

    init(_ list: [Diagnostic]) {
        self.list = list
    }
}
