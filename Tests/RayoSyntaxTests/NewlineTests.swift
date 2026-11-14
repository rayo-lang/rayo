import Testing

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

    @Test func `a line that starts with '.' joins the one above`() {
        #expect(tokens("let hp = e\n    .hp") == ["let", "hp", "=", "e", ".", "hp"])
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

    @Test func `inside '[', newlines are whitespace, and a line that ends in '[' runs on`() {
        #expect(tokens("let a = [\n    1,\n    2\n]\nx") == ["let", "a", "=", "[", "1", ",", "2", "]", "⏎", "x"])
        #expect(tokens("let a = [{ b\nc }]") == ["let", "a", "=", "[", "{", "b", "⏎", "c", "}", "]"])
    }

    @Test("blank lines and comments collapse into one newline")
    func blankLines() {
        #expect(tokens("a\n\n// note\n\nb") == ["a", "⏎", "b"])
        #expect(tokens("\n\na") == ["a"])
    }
}
