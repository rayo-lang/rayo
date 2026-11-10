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
        return (StatementEnds.significantNewlines(raw), lexer.diagnostics)
    }

    /// Lexes the whole file into tokens that end with `.eof`. A file that isn't UTF-8 lexes to `.eof` alone, with
    /// one error at its first invalid byte.
    mutating func lexAll() -> [Token] {
        // A file that isn't UTF-8 has no characters to lex, so its one error points at the first byte that breaks it.
        if let invalid = Self.firstInvalidByte(in: bytes) {
            while index < invalid { advance() }
            let start = location
            advance()
            report(.notUTF8, from: start)
            return [Token(.eof, SourceRange(location, location))]
        }

        // Lex token after token up to the end of the file.
        var tokens: [Token] = []
        while true {
            let token = next()
            // A newline at the start of the file, or one after another newline, ends no line of code.
            if token.kind == .newline, tokens.last?.kind == .newline || tokens.isEmpty {
                continue
            }
            tokens.append(token)
            // The end of the file is the last token.
            if token.kind == .eof { return tokens }
        }
    }

    /// The offset of the first byte in `bytes` that isn't valid UTF-8, or nil if they all are.
    private static func firstInvalidByte(in bytes: [UInt8]) -> Int? {
        var iterator = bytes.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        var offset = 0
        while true {
            switch parser.parseScalar(from: &iterator) {
            // A valid character moves the offset past its bytes.
            case .valid(let scalar):
                offset += scalar.count

            // Every byte was valid.
            case .emptyInput:
                return nil

            // The character at the offset is the first invalid one.
            case .error:
                return offset
            }
        }
    }

    private var location: SourceLocation { SourceLocation(line: line, column: column, offset: index) }

    private func peek(_ ahead: Int = 0) -> UInt8? {
        let position = index + ahead
        return position < bytes.count ? bytes[position] : nil
    }

    /// Moves past the current byte, keeping the line and column on the character after it.
    private mutating func advance() {
        // A newline moves to the first column of the next line.
        if bytes[index] == UInt8(ascii: "\n") {
            line += 1
            column = 1
        } else if bytes[index] & 0xC0 != 0x80 {
            // A byte that starts a character moves one column; a UTF-8 continuation byte stays in its character's.
            column += 1
        }
        index += 1
    }

    private mutating func report(_ code: ErrorCode, from start: SourceLocation) {
        diagnostics.append(Diagnostic(code, at: SourceRange(start, location)))
    }

    /// Lexes the token after any spaces and comments.
    private mutating func next() -> Token {
        // The token starts after the spaces and comments before it.
        skipTrivia()
        let start = location

        // At the end of the bytes, every call lexes `.eof`.
        guard let byte = peek() else {
            return Token(.eof, SourceRange(start, start))
        }
        // A newline is a token, since it may end a statement.
        if byte == UInt8(ascii: "\n") {
            advance()
            return Token(.newline, SourceRange(start, location))
        }
        // A letter or `_` starts a name or a keyword.
        if isIdentifierStart(byte) {
            return lexIdentifier(from: start)
        }
        // A digit starts an integer literal.
        if isDigit(byte) {
            return lexNumber(from: start)
        }
        // The longest punctuation that matches wins, so `->` lexes as one token and not as `-` and `>`.
        for punct in Punct.byLengthDescending where matches(punct.rawValue) {
            for _ in punct.rawValue.utf8 { advance() }
            return Token(.punct(punct), SourceRange(start, location))
        }
        // Any other character starts no token of the language.
        return lexUnexpectedCharacter(from: start)
    }

    /// Lexes the character at `start`, all of its UTF-8 bytes, as one unexpected token. A `"` takes the rest of its
    /// quoted text on the line with it.
    private mutating func lexUnexpectedCharacter(from start: SourceLocation) -> Token {
        // Take the character's continuation bytes with its first.
        advance()
        while let byte = peek(), byte & 0xC0 == 0x80 { advance() }
        let character = String(decoding: bytes[start.offset..<index], as: UTF8.self)

        // A `"` skips its quoted text, so that a bracket inside the quotes can't end the block the parser skips to
        // when it reports the `"`.
        if character == "\"" { skipQuotedText() }
        return Token(.unexpected(character), SourceRange(start, location))
    }

    /// Skips to just past the closing `"` on this line, a `\"` aside, or to the end of the line if there is none.
    private mutating func skipQuotedText() {
        while let byte = peek(), byte != UInt8(ascii: "\""), byte != UInt8(ascii: "\n") {
            advance()
            // A backslash escapes the character after it, unless that is the newline that ends the text.
            if byte == UInt8(ascii: "\\"), let escaped = peek(), escaped != UInt8(ascii: "\n") { advance() }
        }
        // A closing `"` belongs to the text; a newline doesn't, and is lexed next.
        if peek() == UInt8(ascii: "\"") { advance() }
    }

    /// Whether the bytes from the current one on start with `text`.
    private func matches(_ text: String) -> Bool {
        var position = index
        for byte in text.utf8 {
            // The text runs past the end of the bytes, or differs from them here.
            guard position < bytes.count, bytes[position] == byte else { return false }
            position += 1
        }
        return true
    }

    /// Skips the spaces, tabs, carriage returns and comments before the next token.
    private mutating func skipTrivia() {
        while let byte = peek() {
            // A space, tab or carriage return separates tokens and nothing more.
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r") {
                advance()
            } else if byte == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "/") {
                // A line comment runs to the newline, which stays to end the line.
                while let next = peek(), next != UInt8(ascii: "\n") { advance() }
            } else if byte == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "*") {
                // A block comment runs to its matching `*/`.
                skipBlockComment()
            } else {
                // Any other byte starts a token.
                return
            }
        }
    }

    /// Skips a block comment and the comments nested in it, and reports one that the file ends inside.
    private mutating func skipBlockComment() {
        let start = location
        var depth = 0
        repeat {
            // A `/*` opens a comment one level deeper.
            if matches("/*") {
                advance(); advance()
                depth += 1
            } else if matches("*/") {
                // A `*/` closes the innermost open comment.
                advance(); advance()
                depth -= 1
            } else if peek() == nil {
                // The file ends before the comment does.
                report(.unterminatedBlockComment, from: start)
                return
            } else {
                // Any other byte is the comment's text.
                advance()
            }
        } while depth > 0
    }

    /// Lexes a word as a keyword, or else as an identifier.
    private mutating func lexIdentifier(from start: SourceLocation) -> Token {
        while let byte = peek(), isIdentifierContinue(byte) { advance() }
        let text = String(decoding: bytes[start.offset..<index], as: UTF8.self)
        let kind: TokenKind = Keyword(rawValue: text).map { .keyword($0) } ?? .identifier(text)
        return Token(kind, SourceRange(start, location))
    }

    /// Lexes an integer literal in base 10, or after a `0x`, `0b` or `0o` prefix in base 16, 2 or 8. A malformed
    /// literal reports an error and lexes as `.invalid`.
    private mutating func lexNumber(from start: SourceLocation) -> Token {
        let radix = skipRadixPrefix()

        // Read the digits into a 64-bit value, noting whether it overflowed.
        var value: UInt64 = 0
        var overflow = false
        var digits = 0
        while let byte = peek() {
            // An underscore separates digits and adds nothing to the value.
            if byte == UInt8(ascii: "_") { advance(); continue }
            // The literal ends at the first byte that isn't a digit of its radix.
            guard let digit = digitValue(byte), digit < radix else { break }
            let (product, multiplyOverflowed) = value.multipliedReportingOverflow(by: UInt64(radix))
            let (sum, addOverflowed) = product.addingReportingOverflow(UInt64(digit))
            overflow = overflow || multiplyOverflowed || addOverflowed
            value = sum
            digits += 1
            advance()
        }

        // Find what, if anything, is wrong with the literal.
        let error: ErrorCode?
        // A letter or a digit beyond the radix runs on from the digits; the error covers it and the rest of the word.
        if let byte = peek(), isIdentifierContinue(byte) {
            while let next = peek(), isIdentifierContinue(next) { advance() }
            error = .invalidDigit
        } else if digits == 0 {
            // A prefix with no digits after it.
            error = .missingDigits
        } else if overflow {
            // A value too big for 64 bits.
            error = .literalExceeds64Bits
        } else {
            // A well-formed literal.
            error = nil
        }

        // A malformed literal lexes as `.invalid`, so the parser reports no second error for it.
        if let error {
            report(error, from: start)
            return Token(.invalid, SourceRange(start, location))
        }
        return Token(.intLiteral(value), SourceRange(start, location))
    }

    /// Moves past a `0x`, `0b` or `0o` prefix, and returns the radix it names, or 10 where there is none.
    private mutating func skipRadixPrefix() -> Int {
        // Without a `0` and a byte after it, there is no prefix.
        guard peek() == UInt8(ascii: "0"), let marker = peek(1) else { return 10 }

        // The byte after the `0` names the radix.
        let radix =
            switch marker {
            case UInt8(ascii: "x"): 16
            case UInt8(ascii: "b"): 2
            case UInt8(ascii: "o"): 8
            default: 10
            }

        // A prefix's two bytes are no digits of the literal.
        if radix != 10 { advance(); advance() }
        return radix
    }
}

private func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

private func isIdentifierStart(_ byte: UInt8) -> Bool {
    (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
        || byte == UInt8(ascii: "_")
}

private func isIdentifierContinue(_ byte: UInt8) -> Bool { isIdentifierStart(byte) || isDigit(byte) }

private func digitValue(_ byte: UInt8) -> Int? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(byte - UInt8(ascii: "a")) + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(byte - UInt8(ascii: "A")) + 10
    default: return nil
    }
}
