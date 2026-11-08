import RayoDiagnostics
import Testing
@testable import RayoSyntax

/// The tokens of `source`, written as the source spells them, with `⏎` for a newline that ends a statement.
private func tokens(_ source: String) -> [String] {
    let (tokens, diagnostics) = Lexer.tokenize(source)
    #expect(diagnostics.map(\.code) == [])
    return tokens.dropLast().map { $0.kind == .newline ? "⏎" : $0.description }
}

private func lexErrors(_ source: String) -> [ErrorCode] {
    Lexer.tokenize(source).diagnostics.map(\.code)
}

struct NewlineTests {
    @Test("a line that ends in a binary operator continues")
    func binaryOperatorContinues() {
        #expect(tokens("let total = base +\n    bonus * 2") == ["let", "total", "=", "base", "+", "bonus", "*", "2"])
        #expect(tokens("let ok = a >\n    b") == ["let", "ok", "=", "a", ">", "b"])
    }

    @Test("inside '(', newlines are whitespace")
    func parenthesesIgnoreNewlines() {
        #expect(tokens("f(\n    a,\n    3\n)\nx") == ["f", "(", "a", ",", "3", ")", "⏎", "x"])
    }

    @Test("inside '{' the other rules apply")
    func bracesKeepNewlines() {
        #expect(tokens("f({ a\nb })") == ["f", "(", "{", "a", "⏎", "b", "}", ")"])
    }

    @Test("a line that starts with 'else' joins the one above")
    func elseJoins() {
        #expect(tokens("if ready { start() }\nelse { wait() }") ==
            ["if", "ready", "{", "start", "(", ")", "}", "else", "{", "wait", "(", ")", "}"])
    }

    @Test("';' separates statements on one line")
    func semicolon() {
        #expect(tokens("x = 1; y = 2") == ["x", "=", "1", ";", "y", "=", "2"])
    }

    @Test("a line that starts with '-' starts a new statement")
    func minusStartsStatement() {
        #expect(tokens("let a = b\n-c") == ["let", "a", "=", "b", "⏎", "-", "c"])
    }

    @Test("a line that starts with another binary operator joins the one above")
    func binaryOperatorJoins() {
        #expect(tokens("let a = b\n* c") == ["let", "a", "=", "b", "*", "c"])
        #expect(tokens("let a = b\n>= c") == ["let", "a", "=", "b", ">=", "c"])
    }

    @Test("a line continues after '=', '->' and '{', and before '->' and '{'")
    func otherContinuations() {
        #expect(tokens("x =\n1") == ["x", "=", "1"])
        #expect(tokens("x +=\n1") == ["x", "+=", "1"])
        #expect(tokens("func f()\n-> Int {\nx\n}") == ["func", "f", "(", ")", "->", "Int", "{", "x", "⏎", "}"])
        #expect(tokens("if a\n{ b }") == ["if", "a", "{", "b", "}"])
    }

    @Test("blank lines and comments collapse into one newline")
    func blankLines() {
        #expect(tokens("a\n\n// note\n\nb") == ["a", "⏎", "b"])
        #expect(tokens("\n\na") == ["a"])
    }
}

struct TokenTests {
    @Test("integer literals, with radix prefixes and separators")
    func integers() {
        #expect(tokens("0 42 1_000 0xFF 0b1010 0o17") == ["0", "42", "1000", "255", "10", "15"])
    }

    @Test("an integer literal holds 64 bits of magnitude, so -9223372036854775808 lexes")
    func integerMagnitude() {
        #expect(tokens("-9223372036854775808") == ["-", "9223372036854775808"])
        #expect(tokens("18446744073709551615") == ["18446744073709551615"])
        #expect(lexErrors("18446744073709551616") == [.integerLiteralTooLarge])
    }

    @Test("the longest operator wins")
    func longestMatch() {
        #expect(tokens("a>=b -> c += d <= e != f") == ["a", ">=", "b", "->", "c", "+=", "d", "<=", "e", "!=", "f"])
        #expect(tokens("a>b") == ["a", ">", "b"])
    }

    @Test("keywords and identifiers")
    func names() {
        let (lexed, _) = Lexer.tokenize("let keep copy")
        #expect(lexed.map(\.kind) == [.keyword(.let), .identifier("keep"), .keyword(.copy), .eof])
    }

    @Test("comments nest")
    func nestedComments() {
        #expect(tokens("a /* x /* y */ z */ b") == ["a", "b"])
        #expect(lexErrors("a /* x") == [.unterminatedBlockComment])
    }

    @Test("malformed integer literals are reported", arguments: [
        ("let x = 12ab", ErrorCode.invalidDigit),
        ("let x = 0x", .missingDigits),
    ])
    func errors(source: String, expected: ErrorCode) {
        #expect(lexErrors(source) == [expected])
    }

    @Test("a character outside the grammar lexes as an unexpected character, which the parser reports", arguments: [
        "#", ".", "[", "?", "$", "`", "é",
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
        let (lexed, diagnostics) = Lexer.tokenize(source)
        #expect(diagnostics.isEmpty)
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
