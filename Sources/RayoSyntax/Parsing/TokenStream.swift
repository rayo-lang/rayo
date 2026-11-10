import RayoDiagnostics
import RayoSource

/// The tokens of a file, as the parsers of each part of the grammar read them in turn, and the syntax errors found
/// so far. A parser that meets an error reports it here and throws.
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
        // Any other token is reported as `error`.
        guard current.isPunct(punct) else { throw fail(error) }
        return advance()
    }

    func expectIdentifier(else error: ErrorCase) throws(ParseFailure) -> (String, SourceRange) {
        // Any other token is reported as `error`.
        guard case .identifier(let name) = current.kind else { throw fail(error) }
        return (name, advance().range)
    }

    /// Reports `error` at the current token, or the unexpected character the token is, and returns the failure to
    /// throw. A token the lexer reported already is reported no second time.
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

    /// What the parser found in `token`, as an error names it.
    private func found(_ token: Token) -> FoundToken {
        switch token.kind {
        case .newline: .newline
        case .eof: .endOfFile
        default: .token(token.description)
        }
    }
}
