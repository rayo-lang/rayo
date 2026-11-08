import RayoDiagnostics
import RayoSource

/// Turns UTF-8 source into tokens, keeping only the newlines that end statements.
public struct Lexer {
    private let bytes: [UInt8]
    private var index = 0
    private var line = 1
    private var column = 1
    public private(set) var diagnostics: [Diagnostic] = []

    public init(_ source: String) {
        self.init(Array(source.utf8))
    }

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    public static func tokenize(_ source: String) -> (tokens: [Token], diagnostics: [Diagnostic]) {
        tokenize(Array(source.utf8))
    }

    public static func tokenize(_ bytes: [UInt8]) -> (tokens: [Token], diagnostics: [Diagnostic]) {
        var lexer = Lexer(bytes)
        let raw = lexer.lexAll()
        return (significantNewlines(raw), lexer.diagnostics)
    }

    // MARK: Raw tokens

    /// The file's tokens. A file that isn't UTF-8 has none, and one error at its first invalid byte.
    mutating func lexAll() -> [Token] {
        if let invalid = Self.firstInvalidByte(in: bytes) {
            while index < invalid { advance() }
            let start = location
            advance()
            report(.notUTF8, from: start)
            return [Token(.eof, SourceRange(location, location))]
        }
        var tokens: [Token] = []
        while true {
            let token = next()
            if token.kind == .newline, tokens.last?.kind == .newline || tokens.isEmpty {
                continue
            }
            tokens.append(token)
            if token.kind == .eof { return tokens }
        }
    }

    private static func firstInvalidByte(in bytes: [UInt8]) -> Int? {
        var iterator = bytes.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        var offset = 0
        while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid(let scalar): offset += scalar.count
            case .emptyInput: return nil
            case .error: return offset
            }
        }
    }

    private var location: SourceLocation { SourceLocation(line: line, column: column, offset: index) }

    private func peek(_ ahead: Int = 0) -> UInt8? {
        let i = index + ahead
        return i < bytes.count ? bytes[i] : nil
    }

    private mutating func advance() {
        if bytes[index] == UInt8(ascii: "\n") {
            line += 1
            column = 1
        } else if bytes[index] & 0xC0 != 0x80 {
            column += 1
        }
        index += 1
    }

    private mutating func report(_ code: ErrorCode, from start: SourceLocation) {
        diagnostics.append(Diagnostic(code, at: SourceRange(start, location)))
    }

    private mutating func next() -> Token {
        skipTrivia()
        let start = location
        guard let c = peek() else {
            return Token(.eof, SourceRange(start, start))
        }
        if c == UInt8(ascii: "\n") {
            advance()
            return Token(.newline, SourceRange(start, location))
        }
        if isIdentifierStart(c) {
            return lexIdentifier(from: start)
        }
        if isDigit(c) {
            return lexNumber(from: start)
        }
        for punct in Punct.byLengthDescending where matches(punct.rawValue) {
            for _ in punct.rawValue.utf8 { advance() }
            return Token(.punct(punct), SourceRange(start, location))
        }
        return lexUnexpectedCharacter(from: start)
    }

    /// The character at `start`, all of its UTF-8 bytes, as one token. A `"` takes its quoted text with it,
    /// so that a bracket inside the quotes can't end the block the parser skips to when it reports the `"`.
    private mutating func lexUnexpectedCharacter(from start: SourceLocation) -> Token {
        advance()
        while let c = peek(), c & 0xC0 == 0x80 { advance() }
        let character = String(decoding: bytes[start.offset..<index], as: UTF8.self)
        if character == "\"" { skipQuotedText() }
        return Token(.unexpected(character), SourceRange(start, location))
    }

    /// Skips to just past the closing `"` on this line, a `\"` aside, or to the end of the line if there is none.
    private mutating func skipQuotedText() {
        while let c = peek(), c != UInt8(ascii: "\""), c != UInt8(ascii: "\n") {
            advance()
            if c == UInt8(ascii: "\\"), let d = peek(), d != UInt8(ascii: "\n") { advance() }
        }
        if peek() == UInt8(ascii: "\"") { advance() }
    }

    private func matches(_ text: String) -> Bool {
        var i = index
        for byte in text.utf8 {
            guard i < bytes.count, bytes[i] == byte else { return false }
            i += 1
        }
        return true
    }

    private mutating func skipTrivia() {
        while let c = peek() {
            if c == UInt8(ascii: " ") || c == UInt8(ascii: "\t") || c == UInt8(ascii: "\r") {
                advance()
            } else if c == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "/") {
                while let d = peek(), d != UInt8(ascii: "\n") { advance() }
            } else if c == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "*") {
                skipBlockComment()
            } else {
                return
            }
        }
    }

    private mutating func skipBlockComment() {
        let start = location
        var depth = 0
        repeat {
            if matches("/*") {
                advance(); advance()
                depth += 1
            } else if matches("*/") {
                advance(); advance()
                depth -= 1
            } else if peek() == nil {
                report(.unterminatedBlockComment, from: start)
                return
            } else {
                advance()
            }
        } while depth > 0
    }

    private mutating func lexIdentifier(from start: SourceLocation) -> Token {
        while let c = peek(), isIdentifierContinue(c) { advance() }
        let text = String(decoding: bytes[start.offset..<index], as: UTF8.self)
        let kind: TokenKind = Keyword(rawValue: text).map { .keyword($0) } ?? .identifier(text)
        return Token(kind, SourceRange(start, location))
    }

    private mutating func lexNumber(from start: SourceLocation) -> Token {
        var radix = 10
        if peek() == UInt8(ascii: "0"), let p = peek(1) {
            switch p {
            case UInt8(ascii: "x"): radix = 16
            case UInt8(ascii: "b"): radix = 2
            case UInt8(ascii: "o"): radix = 8
            default: break
            }
            if radix != 10 { advance(); advance() }
        }
        var value: UInt64 = 0
        var overflow = false
        var digits = 0
        while let c = peek() {
            if c == UInt8(ascii: "_") { advance(); continue }
            guard let digit = digitValue(c), digit < radix else { break }
            let (product, o1) = value.multipliedReportingOverflow(by: UInt64(radix))
            let (sum, o2) = product.addingReportingOverflow(UInt64(digit))
            overflow = overflow || o1 || o2
            value = sum
            digits += 1
            advance()
        }
        let error: ErrorCode?
        if let c = peek(), isIdentifierContinue(c) {
            while let c = peek(), isIdentifierContinue(c) { advance() }
            error = .invalidDigit
        } else if digits == 0 {
            error = .missingDigits
        } else if overflow {
            error = .integerLiteralTooLarge
        } else {
            error = nil
        }
        if let error {
            report(error, from: start)
            return Token(.invalid, SourceRange(start, location))
        }
        return Token(.intLiteral(value), SourceRange(start, location))
    }

    // MARK: Newlines

    /// Drops the newlines that don't end a statement: inside `(`, after a token that continues the line, and
    /// before a token that joins the line above.
    static func significantNewlines(_ raw: [Token]) -> [Token] {
        var result: [Token] = []
        var brackets: [Punct] = []
        for (i, token) in raw.enumerated() {
            switch token.kind {
            case .punct(.lparen), .punct(.lbrace):
                if case .punct(let p) = token.kind { brackets.append(p) }
            case .punct(.rparen), .punct(.rbrace):
                if !brackets.isEmpty { brackets.removeLast() }
            case .newline:
                if brackets.last == .lparen { continue }
                if let previous = result.last, continuesLine(previous) { continue }
                if i + 1 < raw.count, joinsLine(raw[i + 1]) { continue }
                if result.isEmpty || result.last?.kind == .newline { continue }
            default:
                break
            }
            result.append(token)
        }
        return result
    }

    private static func continuesLine(_ token: Token) -> Bool {
        guard case .punct(let p) = token.kind else { return false }
        return p.binaryOperator != nil || p.assignOperator != nil || p == .arrow || p == .lparen || p == .lbrace
    }

    /// Whether `token` at the start of a line joins it to the line above. A `-` there starts a statement; a
    /// `{` can't start one, so it always opens the block of the line above.
    private static func joinsLine(_ token: Token) -> Bool {
        switch token.kind {
        case .punct(.minus):
            return false
        case .punct(let p):
            return p.binaryOperator != nil || p == .arrow || p == .lbrace
        case .keyword(.else):
            return true
        default:
            return false
        }
    }
}

private func isDigit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }

private func isIdentifierStart(_ c: UInt8) -> Bool {
    (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z")) || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
        || c == UInt8(ascii: "_")
}

private func isIdentifierContinue(_ c: UInt8) -> Bool { isIdentifierStart(c) || isDigit(c) }

private func digitValue(_ c: UInt8) -> Int? {
    switch c {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(c - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(c - UInt8(ascii: "a")) + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(c - UInt8(ascii: "A")) + 10
    default: return nil
    }
}
