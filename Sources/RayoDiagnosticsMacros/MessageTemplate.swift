import SwiftSyntax

/// A code's message as `@Code` gives it: text, and `{label}` placeholders for the case's values, or
/// `{label.property}` placeholders for a property of one.
struct MessageTemplate {
    enum Part {
        /// Text as written in the source, escapes included.
        case text(String)
        /// The value of `label`, or its `property` where the placeholder names one.
        case value(label: String, property: String?)
    }

    var parts: [Part]

    /// The template `expression` holds, or nil when it isn't a one-line string literal without
    /// interpolation. Only `{name}` and `{name.property}` are placeholders, so other braces, and `\u{…}`, are text.
    init?(_ expression: ExprSyntax) {
        guard let source = Self.plainSource(of: expression) else { return nil }
        parts = Self.parts(of: Array(source.unicodeScalars))
    }

    /// The labels the placeholders name, each once, in the order they first appear.
    var placeholderLabels: [String] {
        var labels: [String] = []
        for case .value(let label, _) in parts where !labels.contains(label) {
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
            case .value(let label, nil): "\\(v\(labels.firstIndex(of: label)!))"
            case .value(let label, let property?): "\\(v\(labels.firstIndex(of: label)!).\(property))"
            }
        }.joined()
    }

    /// The source text inside `expression`, when it is a one-line string literal without interpolation.
    private static func plainSource(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.openingPounds == nil,
              literal.openingQuote.tokenKind == .stringQuote else { return nil }
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
            if let placeholder = placeholder(in: scalars, at: index) {
                parts += [.text(String(text)), .value(label: placeholder.label, property: placeholder.property)]
                text = String.UnicodeScalarView()
                index = placeholder.end
            } else {
                text.append(scalars[index])
                index += 1
            }
        }
        return parts + [.text(String(text))]
    }

    /// The `{identifier}` or `{identifier.property}` that starts at `start`: the identifier, the property where
    /// there is one, and the index just past the `}`.
    private static func placeholder(
        in scalars: [Unicode.Scalar], at start: Int,
    ) -> (label: String, property: String?, end: Int)? {
        // A placeholder opens with a brace that starts no `\u{…}` escape, followed by the label.
        guard scalars[start] == "{", !isUnicodeEscape(scalars, braceAt: start),
              let labelEnd = identifierEnd(in: scalars, from: start + 1) else { return nil }

        // A property may follow the label, and a `}` closes the placeholder after either.
        let property = property(in: scalars, at: labelEnd)
        let end = property?.end ?? labelEnd
        guard end < scalars.count, scalars[end] == "}" else { return nil }

        let label = String(String.UnicodeScalarView(scalars[(start + 1)..<labelEnd]))
        return (label, property?.name, end + 1)
    }

    /// The `.identifier` that starts at `start`: the identifier, and the index just past it.
    private static func property(in scalars: [Unicode.Scalar], at start: Int) -> (name: String, end: Int)? {
        // Only a `.` with an identifier after it starts a property.
        guard start < scalars.count, scalars[start] == ".",
              let end = identifierEnd(in: scalars, from: start + 1) else { return nil }
        return (String(String.UnicodeScalarView(scalars[(start + 1)..<end])), end)
    }

    /// Whether the brace at `brace` opens a `\u{…}` escape: it follows a `u` after an odd run of
    /// backslashes, since an even run is that many escaped backslashes.
    private static func isUnicodeEscape(_ scalars: [Unicode.Scalar], braceAt brace: Int) -> Bool {
        guard brace >= 2, scalars[brace - 1] == "u" else { return false }
        var backslashes = 0
        while brace - 2 - backslashes >= 0, scalars[brace - 2 - backslashes] == "\\" { backslashes += 1 }
        return backslashes % 2 == 1
    }

    /// The index just past the Swift identifier that starts at `start`, or nil when none starts there.
    private static func identifierEnd(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        guard start < scalars.count, scalars[start] == "_" || scalars[start].properties.isXIDStart else { return nil }
        var end = start + 1
        while end < scalars.count, scalars[end].properties.isXIDContinue { end += 1 }
        return end
    }
}
