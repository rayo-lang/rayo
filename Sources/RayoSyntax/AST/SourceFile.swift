public import RayoSource

/// A parsed file: its declarations, and the source and tokens they were parsed from.
public struct SourceFile: Sendable {
    /// The file's top-level declarations, in source order, those that failed to parse among them.
    public var declarations: [Declaration]
    /// The source, as UTF-8.
    private let source: [UInt8]
    /// The source's tokens, in order, which leave out its spaces and comments.
    private let tokens: [Token]

    init(declarations: [Declaration], source: [UInt8], tokens: [Token]) {
        self.declarations = declarations
        self.source = source
        self.tokens = tokens
    }

    /// The source text that `range` covers, on one line, for an error to name it by. A gap of spaces, newlines and
    /// comments between tokens is one space, or none inside a bracket or before a `,`. Parentheses around the whole
    /// are left out.
    public func spelling(of range: SourceRange) -> String {
        // The tokens that `range` covers, without the newlines among them or the parentheses around them all.
        var covered = tokens.filter { token in
            token.kind != .newline && token.kind != .eof
                && range.start.offset <= token.range.start.offset && token.range.end.offset <= range.end.offset
        }
        while Self.isParenthesized(covered) {
            covered.removeFirst()
            covered.removeLast()
        }

        // Tokens that touch in the source touch in the spelling, and a gap that keeps a space is one space.
        var spelling = ""
        for (index, token) in covered.enumerated() {
            if index > 0, Self.isSpaced(covered[index - 1], token) { spelling += " " }
            spelling += source.text(of: token.range)
        }
        return spelling
    }

    /// Whether the spelling puts a space between `previous` and `next`: where the source has a gap between them,
    /// except just inside a bracket or before a `,`.
    private static func isSpaced(_ previous: Token, _ next: Token) -> Bool {
        let opensBracket = previous.isPunct(.lparen) || previous.isPunct(.lbracket) || previous.isPunct(.lbrace)
        let closesBracket = next.isPunct(.rparen) || next.isPunct(.rbracket) || next.isPunct(.rbrace)
        let hasGap = previous.range.end.offset < next.range.start.offset
        return hasGap && !opensBracket && !closesBracket && !next.isPunct(.comma)
    }

    /// Whether `tokens` start with a `(` that the last of them closes.
    private static func isParenthesized(_ tokens: [Token]) -> Bool {
        guard tokens.count >= 2, tokens[0].isPunct(.lparen), tokens[tokens.count - 1].isPunct(.rparen) else {
            return false
        }
        // The first `(` is closed where the depth of parentheses first falls back to zero.
        var depth = 0
        for (index, token) in tokens.enumerated() {
            if token.isPunct(.lparen) { depth += 1 }
            if token.isPunct(.rparen) { depth -= 1 }
            if depth == 0 { return index == tokens.count - 1 }
        }
        return false
    }
}
