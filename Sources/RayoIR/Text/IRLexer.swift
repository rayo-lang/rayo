/// Splits Rayo IR's text into tokens, skipping spaces, line breaks and `//` comments.
struct IRLexer: ~Copyable {
    /// The text, as UTF-8.
    private let bytes: [UInt8]
    private var index = 0
    private var line = 1
    private var column = 1

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    /// The tokens of `text`, ending in `.end`. Throws where the text holds a character no token starts with, or a
    /// quoted name that the text doesn't close.
    static func tokens(of text: String) throws(IRTextError) -> [IRToken] {
        var lexer = IRLexer(text)
        var tokens: [IRToken] = []
        while true {
            lexer.skipSpaceAndComments()
            let token = try lexer.nextToken()
            tokens.append(token)
            if token.kind == .end { return tokens }
        }
    }

    /// Moves past spaces, line breaks and comments, which run from `//` to the end of their line.
    private mutating func skipSpaceAndComments() {
        while let byte = peek() {
            if byte == UInt8(ascii: "/"), peek(1) == UInt8(ascii: "/") {
                while let next = peek(), next != UInt8(ascii: "\n") { advance() }
            } else if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t")
                        || byte == UInt8(ascii: "\r") {
                advance()
            } else {
                return
            }
        }
    }

    /// The token that starts at the current byte.
    private mutating func nextToken() throws(IRTextError) -> IRToken {
        let (line, column) = (self.line, self.column)
        let kind = try nextKind()
        return IRToken(kind: kind, line: line, column: column)
    }

    private mutating func nextKind() throws(IRTextError) -> IRToken.Kind {
        guard let byte = peek() else { return .end }

        // A word or a number runs on while its bytes can continue it.
        if isWordByte(byte), !isDigit(byte) { return .word(take(while: isWordByte)) }
        if isDigit(byte) { return try integer() }

        // A quoted name runs to the next quote.
        if byte == UInt8(ascii: "\"") { return try quoted() }

        // `->` is the one symbol of two characters, and every other symbol is one.
        if byte == UInt8(ascii: "-"), peek(1) == UInt8(ascii: ">") {
            advance()
            advance()
            return .symbol("->")
        }
        if "{}(),:=@-.%".utf8.contains(byte) {
            advance()
            return .symbol(String(decoding: [byte], as: UTF8.self))
        }
        throw IRTextError(line: line, column: column, message: "unexpected character '\(Character(.init(byte)))'")
    }

    /// The number of the digits at the current byte. Throws where it doesn't fit in 64 bits.
    private mutating func integer() throws(IRTextError) -> IRToken.Kind {
        let (line, column) = (self.line, self.column)
        let digits = take(while: isDigit)
        guard let value = UInt64(digits) else {
            throw IRTextError(line: line, column: column, message: "the number \(digits) is too large")
        }
        return .integer(value)
    }

    /// The text between the quote at the current byte and the next one. Throws where no quote on the line closes it.
    private mutating func quoted() throws(IRTextError) -> IRToken.Kind {
        let (line, column) = (self.line, self.column)
        advance()
        let start = index
        while let byte = peek(), byte != UInt8(ascii: "\""), byte != UInt8(ascii: "\n") { advance() }
        guard peek() == UInt8(ascii: "\"") else {
            throw IRTextError(line: line, column: column, message: "a quoted name with no closing quote")
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        advance()
        return .string(text)
    }

    /// The bytes from the current one up to the first that `belongs` rejects, as text.
    private mutating func take(while belongs: (UInt8) -> Bool) -> String {
        let start = index
        while let byte = peek(), belongs(byte) { advance() }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private func peek(_ ahead: Int = 0) -> UInt8? {
        index + ahead < bytes.count ? bytes[index + ahead] : nil
    }

    /// Moves past the current byte, onto the next line where it is a line break.
    private mutating func advance() {
        if bytes[index] == UInt8(ascii: "\n") {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }
}

private func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
}

/// Whether `byte` can be part of a word: a letter, a digit or `_`.
private func isWordByte(_ byte: UInt8) -> Bool {
    isDigit(byte) || byte == UInt8(ascii: "_") || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
        || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
}
