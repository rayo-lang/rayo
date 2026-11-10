import RayoDiagnostics
import RayoSource

/// The tokens of a file, as the parsers of each part of the grammar read them in turn, and the syntax errors found
/// so far. A parser that meets an error reports it here and throws, and the sequence it is in skips to its next item.
final class TokenStream {
    /// The `ErrorCode` case of a syntax error, which takes what the parser found where it expected something
    /// else.
    typealias ErrorCase = (FoundToken) -> ErrorCode

    private let tokens: [Token]
    private var position = 0
    private(set) var diagnostics: [Diagnostic]

    /// The tokens of source held as UTF-8, with the errors the lexer found in it.
    init(_ bytes: [UInt8]) {
        let (tokens, diagnostics) = Lexer.tokenize(bytes)
        self.tokens = tokens
        self.diagnostics = diagnostics
    }

    var current: Token { tokens[position] }
    var atEnd: Bool { current.kind == .eof }

    /// The range of the token before the current one.
    var previousRange: SourceRange { tokens[max(position - 1, 0)].range }

    var atStatementEnd: Bool {
        current.kind == .newline || current.isPunct(.semicolon) || current.isPunct(.rbrace) || atEnd
    }

    func peek(_ ahead: Int = 1) -> Token {
        tokens[min(position + ahead, tokens.count - 1)]
    }

    /// The range from the start of `start` to the end of the token before the current one.
    func range(from start: SourceRange) -> SourceRange { SourceRange(start.start, previousRange.end) }

    /// Moves past the current token, unless it ends the file, and returns it.
    @discardableResult
    func advance() -> Token {
        let token = tokens[position]
        // The end of the file stays current, so every read after it finds `.eof`.
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    func consume(_ punct: Punct) -> Bool {
        // Any other token stays current.
        guard current.isPunct(punct) else { return false }
        advance()
        return true
    }

    func consume(_ keyword: Keyword) -> Bool {
        // Any other token stays current.
        guard current.isKeyword(keyword) else { return false }
        advance()
        return true
    }

    @discardableResult
    func expect(_ punct: Punct, else error: ErrorCase) throws(ParseFailure) -> Token {
        // Any other token is the error's.
        guard current.isPunct(punct) else { throw fail(error) }
        return advance()
    }

    func expectIdentifier(else error: ErrorCase) throws(ParseFailure) -> (String, SourceRange) {
        // Any other token is the error's.
        guard case .identifier(let name) = current.kind else { throw fail(error) }
        return (name, advance().range)
    }

    /// Reports `error` at the current token, or the unexpected character the token is, and returns the failure to
    /// throw.
    func fail(_ error: ErrorCase) -> ParseFailure {
        switch current.kind {
        // A malformed literal is the lexer's error, reported already, so nothing more is.
        case .invalid:
            break

        // A character outside the grammar is the error, whatever the parser expected in its place.
        case .unexpected(let character):
            report(.unexpectedCharacter(character: character))

        // Any other token is what the parser found in place of what it expected.
        default:
            report(error(found(current)))
        }
        return ParseFailure()
    }

    /// Reports `code` at the current token.
    func report(_ code: ErrorCode) {
        diagnostics.append(Diagnostic(code, at: current.range))
    }

    /// Parses items separated by newlines or `;`, up to the `}` that closes their block or the end of the file,
    /// which it leaves for the caller. An item that fails is skipped, and its error stays reported.
    func parseSequence<T>(ifUnended unended: ErrorCase, _ item: () throws(ParseFailure) -> T) -> [T] {
        var items: [T] = []
        skipSeparators()
        while !current.isPunct(.rbrace) && !atEnd {
            do {
                items.append(try item())
                // An item that runs on past its end is reported, and the rest of it skipped.
                if !atStatementEnd { throw fail(unended) }
            } catch {
                // An item that failed is skipped, and the sequence goes on with the next one.
                recover()
            }
            skipSeparators()
        }
        return items
    }

    /// After a `(`: parses items separated by commas, with an optional trailing comma, and the `)`.
    func parseList<T>(ifUnclosed unclosed: ErrorCase,
                      _ item: () throws(ParseFailure) -> T) throws(ParseFailure) -> [T] {
        var items: [T] = []
        while !current.isPunct(.rparen) {
            items.append(try item())
            // An item without a comma after it is the last.
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: unclosed)
        return items
    }

    /// What the parser found in `token`, as an error names it.
    private func found(_ token: Token) -> FoundToken {
        switch token.kind {
        case .newline: return .newline
        case .eof: return .endOfFile
        default: return .token(token.description)
        }
    }

    private func skipSeparators() {
        while current.kind == .newline || current.isPunct(.semicolon) { advance() }
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it or the `}` that closes
    /// its block.
    private func recover() {
        // Skip to the newline, `;` or `}` that ends the item, past the brackets the item opens.
        let start = position
        var depth = 0
        loop: while !atEnd {
            switch current.kind {
            // A bracket the item opens is skipped whole, up to the bracket that closes it.
            case .punct(.lbrace), .punct(.lparen):
                depth += 1

            // A `}` outside the item's brackets closes its block, which the sequence stops at; inside, it closes one.
            case .punct(.rbrace):
                if depth == 0 { break loop }
                depth -= 1

            // A `)` closes one of the item's brackets; a stray one is skipped.
            case .punct(.rparen):
                if depth > 0 { depth -= 1 }

            // A newline or `;` outside the item's brackets ends it; inside them, it is skipped.
            case .newline, .punct(.semicolon):
                if depth == 0 { break loop }

            // Every other token is skipped.
            default:
                break
            }
            advance()
        }

        // An item that fails on a token it can't skip past, such as a stray `)`, skips that token, so the sequence
        // goes on.
        if position == start && !atStatementEnd { advance() }
    }
}
