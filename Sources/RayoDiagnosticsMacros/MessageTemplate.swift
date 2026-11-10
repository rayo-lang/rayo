import SwiftSyntax

/// A code's message as `@Code` gives it: text, and `{label}` placeholders for the case's values.
struct MessageTemplate {
    enum Part {
        /// Text as written in the source, escapes included.
        case text(String)
        /// A placeholder for the case's value with that label.
        case value(label: String)
    }

    var parts: [Part]

    /// The template `expression` holds, or nil when it isn't a one-line string literal without
    /// interpolation. Only `{name}` is a placeholder, so other braces, and `\u{…}`, are text.
    init?(_ expression: ExprSyntax) {
        // An expression that isn't a plain string literal holds no template.
        guard let source = Self.plainSource(of: expression) else { return nil }

        parts = Self.parts(of: Array(source.unicodeScalars))
    }

    /// The labels the placeholders name, each once, in the order they first appear.
    var placeholderLabels: [String] {
        // Keep each label the first time a placeholder names it.
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
        // A raw or multi-line literal, or any other expression, is no plain literal.
        guard let literal = expression.as(StringLiteralExprSyntax.self), literal.openingPounds == nil,
              literal.openingQuote.tokenKind == .stringQuote else { return nil }

        // Join the literal's text, which a plain literal holds in segments of text alone.
        var source = ""
        for segment in literal.segments {
            // A segment that interpolates a value makes the literal no plain one.
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            source += plain.content.text
        }
        return source
    }

    /// Splits `scalars` into text and placeholders.
    private static func parts(of scalars: [Unicode.Scalar]) -> [Part] {
        // Read the scalars in order, collecting text up to each placeholder, and the text after the last.
        var parts: [Part] = []
        var text = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if let placeholder = placeholder(in: scalars, at: index) {
                // A placeholder ends the text before it, and the next text starts after it.
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
        // Only a brace that opens no escape, then an identifier, then a closing brace make a placeholder.
        guard scalars[start] == "{", !isUnicodeEscape(scalars, braceAt: start),
              let labelEnd = identifierEnd(in: scalars, from: start + 1), labelEnd < scalars.count,
              scalars[labelEnd] == "}" else { return nil }

        // The label is the identifier between the braces, and the placeholder ends past the closing one.
        let label = String(String.UnicodeScalarView(scalars[(start + 1)..<labelEnd]))
        return (label, labelEnd + 1)
    }

    /// Whether the brace at `brace` opens a `\u{…}` escape.
    private static func isUnicodeEscape(_ scalars: [Unicode.Scalar], braceAt brace: Int) -> Bool {
        // A brace without a `u` before it, and room before that for a backslash, opens no escape.
        guard brace >= 2, scalars[brace - 1] == "u" else { return false }

        // The `u` starts an escape after an odd run of backslashes, since an even run is that many escaped ones.
        var backslashes = 0
        while brace - 2 - backslashes >= 0, scalars[brace - 2 - backslashes] == "\\" { backslashes += 1 }
        return backslashes % 2 == 1
    }

    /// The index just past the Swift identifier that starts at `start`, or nil when none starts there.
    private static func identifierEnd(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        // An identifier starts with `_` or a letter that may start one.
        guard start < scalars.count, scalars[start] == "_" || scalars[start].properties.isXIDStart else { return nil }

        // It runs on through every scalar that may continue one.
        var end = start + 1
        while end < scalars.count, scalars[end].properties.isXIDContinue { end += 1 }
        return end
    }
}
