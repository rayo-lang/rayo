import Testing
@testable import RayoSyntax

/// The tokens of `source`, written as the source spells them, with `⏎` for a newline that ends a statement.
private func tokens(_ source: String) -> [String] {
    let (tokens, diagnostics) = Lexer.tokenize(source)
    #expect(diagnostics.map(\.description) == [])
    return tokens.dropLast().map { $0.kind == .newline ? "⏎" : $0.description }
}

private func lexErrors(_ source: String) -> [String] {
    Lexer.tokenize(source).diagnostics.map(\.description)
}

struct NewlineTests {
    @Test("a line that ends in a binary operator continues")
    func binaryOperatorContinues() {
        #expect(tokens("let total = base +\n    bonus * 2") == ["let", "total", "=", "base", "+", "bonus", "*", "2"])
    }

    @Test("a line that starts with '.' joins the one above")
    func dotJoins() {
        #expect(tokens("let n = xs\n    .count\nf()") == ["let", "n", "=", "xs", ".", "count", "⏎", "f", "(", ")"])
    }

    @Test("inside ( and [, newlines are whitespace")
    func bracketsIgnoreNewlines() {
        #expect(tokens("spawn(\n    at: origin,\n    count: 3\n)\nx") ==
            ["spawn", "(", "at", ":", "origin", ",", "count", ":", "3", ")", "⏎", "x"])
        #expect(tokens("[\n1\n]") == ["[", "1", "]"])
    }

    @Test("inside { the other rules apply")
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

    @Test("a line that starts with a prefix-capable operator starts a new statement")
    func prefixOperatorStartsStatement() {
        #expect(tokens("let a = b\n-c") == ["let", "a", "=", "b", "⏎", "-", "c"])
        #expect(tokens("let a = b\n&c") == ["let", "a", "=", "b", "⏎", "&", "c"])
        #expect(tokens("let a = b\n..<c") == ["let", "a", "=", "b", "⏎", "..<", "c"])
    }

    @Test("a line that starts with another binary operator joins, '>' included")
    func binaryOperatorJoins() {
        #expect(tokens("let a = b\n* c") == ["let", "a", "=", "b", "*", "c"])
        #expect(tokens("let a = b\n> c") == ["let", "a", "=", "b", ">", "c"])
    }

    @Test("a line that ends in '>' keeps its newline, for the parser to decide")
    func greaterKeepsNewline() {
        #expect(tokens("let a: List<Int>\nf()") == ["let", "a", ":", "List", "<", "Int", ">", "⏎", "f", "(", ")"])
    }

    @Test("a line continues after '=', '->', ',' and '{', and before '->'")
    func otherContinuations() {
        #expect(tokens("x =\n1") == ["x", "=", "1"])
        #expect(tokens("func f()\n-> Int {\nx\n}") == ["func", "f", "(", ")", "->", "Int", "{", "x", "⏎", "}"])
    }

    @Test("blank lines and comments collapse into one newline")
    func blankLines() {
        #expect(tokens("a\n\n// note\n\nb") == ["a", "⏎", "b"])
        #expect(tokens("\n\na") == ["a"])
    }

    @Test("a line continues after ',' outside brackets")
    func commaContinues() {
        #expect(tokens("a,\nb") == ["a", ",", "b"])
    }

    @Test("a line that starts with 'where', 'catch' or 'throws' joins the one above", arguments: [
        "where", "catch", "throws",
    ])
    func keywordJoins(keyword: String) {
        #expect(tokens("a\n\(keyword) b") == ["a", keyword, "b"])
    }

    @Test("a line that is an attribute continues into the declaration below it", arguments: [
        ("@reflect\nstruct S", ["@", "reflect", "struct", "S"]),
        ("@packed(4)\nstruct S", ["@", "packed", "(", "4", ")", "struct", "S"]),
        ("@ui.Bounds\nfunc f", ["@", "ui", ".", "Bounds", "func", "f"]),
        ("@checks(.all)\ndo", ["@", "checks", "(", ".", "all", ")", "do"]),
        ("f(x)\ng()", ["f", "(", "x", ")", "⏎", "g", "(", ")"]),
        ("a.b\nc", ["a", ".", "b", "⏎", "c"]),
    ])
    func attributeContinues(source: String, expected: [String]) {
        #expect(tokens(source) == expected)
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
        #expect(lexErrors("18446744073709551616") == ["1:1: error: integer literal doesn't fit in 64 bits"])
    }

    @Test("'>' is always alone, so nested generic arguments close")
    func greaterAlone() {
        #expect(tokens("List<List<Int>>") == ["List", "<", "List", "<", "Int", ">", ">"])
        #expect(tokens("a >= b") == ["a", ">", "=", "b"])
    }

    @Test("the longest operator wins")
    func longestMatch() {
        #expect(tokens("a..<b -> c += d <<= e") == ["a", "..<", "b", "->", "c", "+=", "d", "<<=", "e"])
    }

    @Test("keywords, identifiers, backticks and closure shorthand names")
    func names() {
        let (lexed, _) = Lexer.tokenize("let `let` $0 keep")
        #expect(lexed.map(\.kind) == [.keyword(.let), .identifier("let"), .identifier("$0"), .identifier("keep"), .eof])
    }

    @Test("comments nest")
    func nestedComments() {
        #expect(tokens("a /* x /* y */ z */ b") == ["a", "b"])
        #expect(lexErrors("a /* x") == ["1:3: error: unterminated block comment"])
    }

    @Test("whitespace before a token is recorded")
    func spaceBefore() {
        let (lexed, _) = Lexer.tokenize("a>= b")
        #expect(lexed.map(\.spaceBefore) == [false, false, false, true, false])
    }

    @Test("lexical errors are reported where they start", arguments: [
        ("let s = \"hi\"", "1:9: error: string literals aren't supported yet"),
        ("let f = 1.5", "1:9: error: floating-point literals aren't supported yet"),
        ("let x = 12ab", "1:9: error: invalid digit in integer literal"),
        ("let x = 0x", "1:9: error: expected digits after the radix prefix"),
        ("a # b", "1:3: error: unexpected character"),
        ("$x", "1:1: error: unexpected character"),
        ("`abc", "1:1: error: unterminated '`' identifier"),
        ("é", "1:1: error: unexpected character"),
    ])
    func errors(source: String, expected: String) {
        #expect(lexErrors(source) == [expected])
    }

    @Test("a column counts characters, not bytes")
    func columns() {
        #expect(lexErrors("é é") == ["1:1: error: unexpected character", "1:3: error: unexpected character"])
    }

    @Test("a string literal is skipped whole, escaped quotes included, and lexing goes on after it")
    func stringSkipped() {
        let (lexed, diagnostics) = Lexer.tokenize("f(\"a\\\"b\", c)")
        #expect(diagnostics.count == 1)
        #expect(lexed.map(\.description) == ["f", "(", "invalid token", ",", "c", ")", "end of file"])
    }

    @Test("an unterminated string literal ends at its line")
    func unterminatedString() {
        let (lexed, diagnostics) = Lexer.tokenize("let s = \"abc\nx")
        #expect(diagnostics.count == 1)
        #expect(lexed.map(\.description) == ["let", "s", "=", "invalid token", "newline", "x", "end of file"])
    }
}
