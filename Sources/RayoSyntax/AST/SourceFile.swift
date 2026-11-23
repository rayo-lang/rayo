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

    /// The source that `range` covers as one line of Rayo, for an error to name it by: without comments or the
    /// parentheses around the whole, and with a `;` for each newline that ends a statement.
    public func spelling(of range: SourceRange) -> String {
        // The tokens that `range` covers, without the parentheses around them all.
        var covered = tokens.filter { token in
            token.kind != .eof
                && range.start.offset <= token.range.start.offset && token.range.end.offset <= range.end.offset
        }
        while Self.isParenthesized(covered) {
            covered.removeFirst()
            covered.removeLast()
        }

        // Join the tokens, writing a newline that ends a statement as a `;`, except before the `}` that ends its
        // block, since the `}` ends the statement too.
        var spelling = ""
        var previous: Token?
        var endsStatement = false
        for token in covered {
            if token.kind == .newline {
                endsStatement = true
                continue
            }
            if let previous {
                if endsStatement, !token.isPunct(.rbrace) { spelling += ";" }
                if Self.isSpaced(previous, token) { spelling += " " }
            }
            spelling += source.text(of: token.range)
            previous = token
            endsStatement = false
        }
        return spelling
    }

    /// Whether the spelling puts a space between `previous` and `next`: where the source has a gap between them,
    /// except just inside `( )` or `[ ]`, before a `,`, and before a member's `.` that starts its own line.
    private static func isSpaced(_ previous: Token, _ next: Token) -> Bool {
        let hasGap = previous.range.end.offset < next.range.start.offset
        let opensBracket = previous.isPunct(.lparen) || previous.isPunct(.lbracket)
        let closesBracket = next.isPunct(.rparen) || next.isPunct(.rbracket)
        return hasGap && !opensBracket && !closesBracket && !next.isPunct(.comma)
            && !startsMemberLine(previous, next)
    }

    /// Whether `next` is a member's `.` that starts its own line, after `previous` ends the value it is a member of.
    /// A `.` after anything else, such as a `,`, starts an implicit member, and keeps its space.
    private static func startsMemberLine(_ previous: Token, _ next: Token) -> Bool {
        guard next.isPunct(.dot), previous.range.end.line < next.range.start.line else { return false }
        return switch previous.kind {
        case .identifier, .intLiteral, .keyword(.self), .keyword(.true), .keyword(.false): true
        case .punct(.rparen), .punct(.rbracket): true
        default: false
        }
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
