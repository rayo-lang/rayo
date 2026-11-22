import RayoDiagnostics
import Testing
import RayoSyntax

struct TokenTests {
    @Test("integer literals, with radix prefixes and separators")
    func integers() {
        #expect(tokens("0 42 1_000 0xFF 0b1010 0o17") == ["0", "42", "1000", "255", "10", "15"])
    }

    @Test("an integer literal holds 64 bits of magnitude, so -9223372036854775808 lexes")
    func integerMagnitude() {
        #expect(tokens("-9223372036854775808") == ["-", "9223372036854775808"])
        #expect(tokens("18446744073709551615") == ["18446744073709551615"])
        #expect(lexErrors("18446744073709551616") == [.literalExceeds64Bits])
    }

    @Test("the longest operator wins")
    func longestMatch() {
        #expect(tokens("a>=b -> c += d <= e != f") == ["a", ">=", "b", "->", "c", "+=", "d", "<=", "e", "!=", "f"])
        #expect(tokens("a>b") == ["a", ">", "b"])
    }

    @Test func `a '.' is a token of its own, between a value and its member`() {
        #expect(tokens("e.hp.max") == ["e", ".", "hp", ".", "max"])
    }

    @Test func `keywords and identifiers`() {
        let (lexed, _) = Lexer.tokenize("let keep copy consume struct self mutable owned mutating")
        #expect(lexed.map(\.kind) == [
            .keyword(.let), .identifier("keep"), .keyword(.copy), .keyword(.consume), .keyword(.struct),
            .keyword(.`self`), .keyword(.mutable), .keyword(.owned), .keyword(.mutating), .eof,
        ])
    }

    @Test func `a '&' is a token of its own, and '&&' stays one token`() {
        #expect(tokens("f(&x) && y") == ["f", "(", "&", "x", ")", "&&", "y"])
    }

    @Test("comments nest")
    func nestedComments() {
        #expect(tokens("a /* x /* y */ z */ b") == ["a", "b"])
        #expect(lexErrors("a /* x") == [.unterminatedBlockComment])
    }

    @Test("a malformed integer literal is reported, and the error covers the literal", arguments: [
        ("let x = 12ab", ErrorCode.invalidDigit(digit: "a", base: "decimal"), "12ab"),
        ("let x = 0x", .missingDigits(prefix: "0x"), "0x"),
        ("let x = 18446744073709551616", .literalExceeds64Bits, "18446744073709551616"),
    ])
    func errors(source: String, expected: ErrorCode, literal: String) {
        #expect(lexErrors(source) == [expected])
        #expect(lexCoveredText(source) == [literal])
    }

    @Test(arguments: [
        ("12ab", "'a' isn't a digit in decimal"),
        ("0b102", "'2' isn't a digit in binary"),
        ("0o18", "'8' isn't a digit in octal"),
        ("0xfg", "'g' isn't a digit in hexadecimal"),
        ("0x", "expected digits after '0x'"),
        ("0b_", "expected digits after '0b'"),
        ("18446744073709551616", "the integer literal doesn't fit in 64 bits"),
        ("a /* x /* y */", "the block comment has no closing '*/'"),
    ])
    func `a lexing error's message names what is wrong with the text`(source: String, message: String) {
        #expect(Lexer.tokenize(source).diagnostics.map(\.code.message) == [message])
    }

    @Test("a character outside the grammar lexes as an unexpected character, which the parser reports", arguments: [
        "#", "?", "$", "`", "é",
    ])
    func unexpected(character: String) {
        let (lexed, diagnostics) = Lexer.tokenize("a \(character) b")
        #expect(diagnostics.isEmpty)
        #expect(lexed.map(\.kind) == [.identifier("a"), .unexpected(character), .identifier("b"), .eof])
    }

    @Test("a '\"' is one unexpected token up to its closing '\"' on the line, escaped quotes included",
          arguments: [
        ("a \"x} y\" b", "\"x} y\""),
        ("a \"x\\\"}\" b", "\"x\\\"}\""),
        ("a \"x}\nb", "\"x}"),
    ])
    func quoted(source: String, quoted: String) throws {
        // The lexer reports nothing; the parser reports the `"`.
        let (lexed, diagnostics) = Lexer.tokenize(source)
        #expect(diagnostics.isEmpty)

        // The token after `a` is the `"`, and it covers the quoted text.
        let token = try #require(lexed.dropFirst().first)
        #expect(token.kind == .unexpected("\""))
        let text = Array(source.utf8)[token.range.start.offset..<token.range.end.offset]
        #expect(String(decoding: text, as: UTF8.self) == quoted)

        #expect(lexed.last(where: { $0.kind != .eof })?.kind == .identifier("b"))
    }

    @Test("a column counts characters, not bytes")
    func columns() {
        let (lexed, _) = Lexer.tokenize("é é")
        #expect(lexed.map(\.range.start.column) == [1, 3, 4])
    }
}

/// The codes of the errors the lexer reports for `source`.
private func lexErrors(_ source: String) -> [ErrorCode] {
    Lexer.tokenize(source).diagnostics.map(\.code)
}

/// The source text each error the lexer reports for `source` covers.
private func lexCoveredText(_ source: String) -> [String] {
    let bytes = Array(source.utf8)
    return Lexer.tokenize(source).diagnostics.map {
        String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self)
    }
}
