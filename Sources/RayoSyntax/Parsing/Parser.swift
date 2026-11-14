package import RayoDiagnostics
internal import RayoSource

/// A recursive-descent parser. It reports what it can't parse and recovers at the next statement, so one
/// run lists every syntax error, after the lexer's.
package struct Parser: ~Copyable {
    /// The `ErrorCode` case of a syntax error, which takes what the parser found where it expected something
    /// else.
    typealias ErrorCase = (FoundToken) -> ErrorCode

    /// The source, as UTF-8.
    private let bytes: [UInt8]
    private let tokens: [Token]
    private var position = 0
    private var diagnostics: [Diagnostic]

    /// A parser of `bytes`, held as UTF-8, which lex to `tokens`, at the first token, with the lexer's errors,
    /// `lexerErrors`, as the first diagnostics.
    private init(_ bytes: [UInt8], tokens: [Token], lexerErrors: [Diagnostic]) {
        self.bytes = bytes
        self.tokens = tokens
        diagnostics = lexerErrors
    }

    package static func parse(_ source: String) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        let (file, diagnostics) = parse(Array(source.utf8))
        // A string is UTF-8, so it always parses to a file.
        guard let file else { preconditionFailure("a string is UTF-8") }
        return (file, diagnostics)
    }

    /// Parses `bytes`, with the lexer's and the parser's diagnostics in source order. Bytes that aren't UTF-8 can't
    /// be read as text at all, and parse to no file.
    package static func parse(_ bytes: [UInt8]) -> (file: SourceFile?, diagnostics: [Diagnostic]) {
        let (tokens, lexerErrors) = Lexer.tokenize(bytes)
        guard let tokens else { return (nil, lexerErrors) }

        var parser = Parser(bytes, tokens: tokens, lexerErrors: lexerErrors)
        let file = parser.parseFile()
        return (file, parser.diagnostics.inSourceOrder)
    }

    var current: Token { tokens[position] }
    var atEnd: Bool { current.kind == .eof }

    /// The text of the source that `range` covers.
    func text(of range: SourceRange) -> String {
        String(decoding: bytes[range.start.offset..<range.end.offset], as: UTF8.self)
    }

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
    mutating func advance() -> Token {
        let token = tokens[position]
        // The end of the file stays current, so every read after it finds `.eof`.
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    mutating func consume(_ punct: Punct) -> Bool {
        // Any other token stays current.
        guard current.isPunct(punct) else { return false }
        advance()
        return true
    }

    mutating func consume(_ keyword: Keyword) -> Bool {
        // Any other token stays current.
        guard current.isKeyword(keyword) else { return false }
        advance()
        return true
    }

    @discardableResult
    mutating func expect(_ punct: Punct, else error: ErrorCase) throws(ParseFailure) -> Token {
        // Any other token is reported as `error`.
        guard current.isPunct(punct) else { throw fail(error) }
        return advance()
    }

    mutating func expectIdentifier(else error: ErrorCase) throws(ParseFailure) -> (String, SourceRange) {
        // Any other token is reported as `error`.
        guard case .identifier(let name) = current.kind else { throw fail(error) }
        return (name, advance().range)
    }

    /// Reports `error` at the current token, or the unexpected character the token is, and returns the failure to
    /// throw. A token the lexer reported already is reported no second time.
    mutating func fail(_ error: ErrorCase) -> ParseFailure {
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
    mutating func report(_ code: ErrorCode) {
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
