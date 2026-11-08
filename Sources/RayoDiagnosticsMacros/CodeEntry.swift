import SwiftDiagnostics
import SwiftSyntax

/// One case of a `@Diagnostics` enum, as its `@Code` describes it.
struct CodeEntry {
    var name: String
    /// The labels of the case's values, in order.
    var labels: [String]
    var number: Int
    /// The message's text, as Swift string-literal source, in which `{label}` stands for a value.
    var template: String
    var isNotSupported: Bool
    /// Where the number and the message are written, for errors about them.
    var numberNode: Syntax
    var messageNode: Syntax

    /// Reads `caseDecl`'s entry, or returns the errors that keep it from having one.
    static func read(_ caseDecl: EnumCaseDeclSyntax) -> Result<CodeEntry, Errors> {
        guard caseDecl.elements.count == 1, let element = caseDecl.elements.first else {
            return .failure(Errors([Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.oneCasePerCode)]))
        }
        let name = element.name.text
        guard let code = caseDecl.attributes.lazy.compactMap({ $0.as(AttributeSyntax.self) })
            .first(where: { $0.attributeName.trimmedDescription == "Code" }),
              case .argumentList(let arguments) = code.arguments, arguments.count == 2,
              let numberArgument = arguments.first, let messageArgument = arguments.last
        else {
            return .failure(Errors([Diagnostic(node: caseDecl.caseKeyword, message: CodeTableError.caseWithoutCode(name))]))
        }
        var errors: [Diagnostic] = []
        let parameters = element.parameterClause?.parameters.map { $0 } ?? []
        for parameter in parameters where parameter.firstName == nil {
            errors.append(Diagnostic(node: parameter, message: CodeTableError.unlabeledValue(name)))
        }
        let number = numberArgument.expression.as(IntegerLiteralExprSyntax.self).flatMap { Int($0.literal.text) }
        if number == nil {
            errors.append(Diagnostic(node: numberArgument.expression, message: CodeTableError.numberNotLiteral))
        }
        let template = plainText(of: messageArgument.expression)
        if template == nil {
            errors.append(Diagnostic(node: messageArgument.expression, message: CodeTableError.messageNotPlain))
        }
        guard let number, let template, errors.isEmpty else { return .failure(Errors(errors)) }
        return .success(CodeEntry(name: name, labels: parameters.compactMap { $0.firstName?.text }, number: number,
                                  template: template, isNotSupported: messageArgument.label?.text == "notSupported",
                                  numberNode: Syntax(numberArgument.expression),
                                  messageNode: Syntax(messageArgument.expression)))
    }

    /// The source text inside `expression`, when it is a one-line string literal without interpolation.
    private static func plainText(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.openingPounds == nil,
              literal.openingQuote.tokenKind == .stringQuote else { return nil }
        var text = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            text += plain.content.text
        }
        return text
    }

    /// A piece of the message: text as written, or a placeholder's label.
    enum Part {
        case text(Substring)
        case value(String)
    }

    var parts: [Part] {
        var parts: [Part] = []
        var rest = template[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            parts.append(.text(rest[..<open]))
            parts.append(.value(String(rest[rest.index(after: open)..<close])))
            rest = rest[rest.index(after: close)...]
        }
        parts.append(.text(rest))
        return parts
    }

    /// The labels that the message's placeholders name, in order, repeats included.
    var placeholders: [String] {
        parts.compactMap { if case .value(let label) = $0 { label } else { nil } }
    }

    /// The message as a Swift string literal that interpolates the case's values.
    var messageLiteral: String {
        let source = parts.map { part in
            switch part {
            case .text(let text): String(text)
            case .value(let label): "\\(\(label))"
            }
        }.joined()
        return "\"\(source)\(isNotSupported ? " isn't supported yet" : "")\""
    }

    /// The pattern that matches the case and binds its values to their labels.
    var bindingPattern: String {
        labels.isEmpty ? ".\(name)" : ".\(name)(\(labels.map { "let \($0)" }.joined(separator: ", ")))"
    }
}

/// Errors found while reading a `@Diagnostics` enum.
struct Errors: Error {
    var list: [Diagnostic]

    init(_ list: [Diagnostic]) {
        self.list = list
    }
}
