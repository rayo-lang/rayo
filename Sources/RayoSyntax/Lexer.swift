/// Turns UTF-8 source into tokens, keeping only the newlines that end statements.
public struct Lexer {
    private let bytes: [UInt8]
    private var index = 0
    private var line = 1
    private var column = 1
    private var sawSpace = false
    public private(set) var diagnostics: [Diagnostic] = []

    public init(_ source: String) {
        bytes = Array(source.utf8)
    }

    public static func tokenize(_ source: String) -> (tokens: [Token], diagnostics: [Diagnostic]) {
        var lexer = Lexer(source)
        let raw = lexer.lexAll()
        return (significantNewlines(raw), lexer.diagnostics)
    }

    // MARK: Raw tokens

    mutating func lexAll() -> [Token] {
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

    private mutating func error(_ message: String, from start: SourceLocation) {
        diagnostics.append(.error(message, at: SourceRange(start, location)))
    }

    private mutating func next() -> Token {
        sawSpace = false
        skipTrivia()
        let start = location
        guard let c = peek() else {
            return Token(.eof, SourceRange(start, start), spaceBefore: sawSpace)
        }
        if c == UInt8(ascii: "\n") {
            advance()
            return Token(.newline, SourceRange(start, location), spaceBefore: sawSpace)
        }
        if isIdentifierStart(c) {
            return lexIdentifier(from: start)
        }
        if isDigit(c) {
            return lexNumber(from: start)
        }
        if c == UInt8(ascii: "`") {
            advance()
            let nameStart = index
            while let d = peek(), isIdentifierContinue(d) { advance() }
            let name = String(decoding: bytes[nameStart..<index], as: UTF8.self)
            if peek() == UInt8(ascii: "`") { advance() } else { error("unterminated '`' identifier", from: start) }
            return Token(.identifier(name), SourceRange(start, location), spaceBefore: sawSpace)
        }
        if c == UInt8(ascii: "$"), let d = peek(1), isDigit(d) {
            advance()
            while let d = peek(), isDigit(d) { advance() }
            let name = String(decoding: bytes[start.offset..<index], as: UTF8.self)
            return Token(.identifier(name), SourceRange(start, location), spaceBefore: sawSpace)
        }
        for punct in Punct.byLengthDescending where matches(punct.rawValue) {
            for _ in punct.rawValue.utf8 { advance() }
            return Token(.punct(punct), SourceRange(start, location), spaceBefore: sawSpace)
        }
        if c == UInt8(ascii: "\"") {
            skipStringLiteral()
            error("string literals aren't supported yet", from: start)
        } else {
            advance()
            while let d = peek(), d & 0xC0 == 0x80 { advance() }
            error("unexpected character", from: start)
        }
        return Token(.invalid, SourceRange(start, location), spaceBefore: sawSpace)
    }

    /// Skips a string literal to its closing quote, or to the end of its line if it has none.
    private mutating func skipStringLiteral() {
        advance()
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
                sawSpace = true
            } else if c == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "/") {
                while let d = peek(), d != UInt8(ascii: "\n") { advance() }
                sawSpace = true
            } else if c == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "*") {
                skipBlockComment()
                sawSpace = true
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
                error("unterminated block comment", from: start)
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
        return Token(kind, SourceRange(start, location), spaceBefore: sawSpace)
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
        let message: String?
        if radix == 10, peek() == UInt8(ascii: "."), let d = peek(1), isDigit(d) {
            advance()
            while let c = peek(), isIdentifierContinue(c) { advance() }
            message = "floating-point literals aren't supported yet"
        } else if let c = peek(), isIdentifierContinue(c) {
            while let c = peek(), isIdentifierContinue(c) { advance() }
            message = "invalid digit in integer literal"
        } else if digits == 0 {
            message = "expected digits after the radix prefix"
        } else if overflow {
            message = "integer literal doesn't fit in 64 bits"
        } else {
            message = nil
        }
        if let message {
            error(message, from: start)
            return Token(.invalid, SourceRange(start, location), spaceBefore: sawSpace)
        }
        return Token(.intLiteral(value), SourceRange(start, location), spaceBefore: sawSpace)
    }

    // MARK: Newlines

    /// Drops the newlines that don't end a statement: inside `(` or `[`, after a token that continues the
    /// line, and before a token that joins the line above. Only the parser knows whether a `>` at the end
    /// of a line compares or closes generic arguments, so it drops the newline after a comparison `>`.
    static func significantNewlines(_ raw: [Token]) -> [Token] {
        var result: [Token] = []
        var brackets: [Punct] = []
        for (i, token) in raw.enumerated() {
            switch token.kind {
            case .punct(.lparen), .punct(.lbracket), .punct(.lbrace):
                if case .punct(let p) = token.kind { brackets.append(p) }
            case .punct(.rparen), .punct(.rbracket), .punct(.rbrace):
                if !brackets.isEmpty { brackets.removeLast() }
            case .newline:
                if let open = brackets.last, open == .lparen || open == .lbracket { continue }
                if let previous = result.last, continuesLine(previous) { continue }
                if endsInAttribute(result) { continue }
                if i + 1 < raw.count, joinsLine(raw[i + 1]) { continue }
                if result.isEmpty || result.last?.kind == .newline { continue }
            default:
                break
            }
            result.append(token)
        }
        return result
    }

    static func continuesLine(_ token: Token) -> Bool {
        guard case .punct(let p) = token.kind else { return false }
        return p.isBinaryOperator || p.isAssignment || p == .arrow || p == .comma
            || p == .lparen || p == .lbracket || p == .lbrace
    }

    /// Whether `tokens` ends in an attribute: `@`, a name that may have `.` parts, and optional
    /// arguments in parentheses, as in `@reflect`, `@ui.Bounds` and `@packed(4)`.
    static func endsInAttribute(_ tokens: [Token]) -> Bool {
        var i = tokens.count - 1
        if i >= 0, tokens[i].isPunct(.rparen) {
            var depth = 0
            while i >= 0 {
                if tokens[i].isPunct(.rparen) { depth += 1 }
                if tokens[i].isPunct(.lparen) { depth -= 1 }
                if depth == 0 { break }
                i -= 1
            }
            i -= 1
        }
        while i >= 1, isName(tokens[i]) {
            if tokens[i - 1].isPunct(.at) { return true }
            guard tokens[i - 1].isPunct(.dot) else { return false }
            i -= 2
        }
        return false
    }

    private static func isName(_ token: Token) -> Bool {
        switch token.kind {
        case .identifier, .keyword: return true
        default: return false
        }
    }

    static func joinsLine(_ token: Token) -> Bool {
        switch token.kind {
        case .punct(.dot), .punct(.arrow), .punct(.greater):
            return true
        case .punct(let p):
            return p.isBinaryOperator && p != .minus && p != .amp && p != .halfOpenRange && p != .closedRange
        case .keyword(.else), .keyword(.catch), .keyword(.where), .keyword(.throws):
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
