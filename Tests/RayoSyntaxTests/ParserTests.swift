import RayoDiagnostics
import Testing
import RayoSyntax

private func errors(_ source: String) -> [ErrorCode] {
    Parser.parse(source).diagnostics.map(\.code)
}

struct ParserErrorTests {
    @Test("the parser recovers at the next statement, and reports every error")
    func statementRecovery() {
        #expect(errors("func f() {\n    let = 1\n    let y = 2\n    x = )\n}") == [
            .expected(what: .bindingName, found: .token("=")), .expected(what: .expression, found: .token(")")),
        ])
    }

    @Test("a declaration whose header fails is skipped, and the parser goes on at the next declaration")
    func declarationRecovery() {
        #expect(errors("func f(x) {\n    print(1)\n}\nfunc g() { copy }") == [
            .expected(what: .parenthesisPair, found: .token("x")), .expected(what: .copiedName, found: .token("}")),
        ])
    }

    @Test("declarations are separated by newlines or ';'")
    func separated() {
        #expect(errors("func a() {}\n\nfunc b() -> Int { 1 }; func c() {}") == [])
        #expect(errors("func a() {} func b() {}") == [.expected(what: .declarationEnd, found: .token("func"))])
    }

    @Test("the lexer's and the parser's errors come in source order")
    func sourceOrder() {
        #expect(errors("func f() {\n    let = 1\n    let s = 0x\n}") == [
            .expected(what: .bindingName, found: .token("=")), .missingDigits,
        ])
    }

    @Test("a statement that holds unexpected characters is reported once, at the first")
    func unexpectedOncePerStatement() {
        #expect(errors("func f() {\n    print(\"it's a.b\")\n    x[0] = 2\n}") == [
            .unexpectedCharacter(character: "\""), .unexpectedCharacter(character: "["),
        ])
        #expect(errors("func f() {\n    print(\"}\")\n    print(1)\n}") == [.unexpectedCharacter(character: "\"")])
    }

    @Test("an unclosed block is reported at the end of the file")
    func unclosed() {
        #expect(errors("func f() {\n    x = 1\n") == [.expected(what: .blockClose, found: .endOfFile)])
    }

    @Test("a stray '}' is reported and skipped")
    func strayBrace() {
        #expect(errors("}\nfunc f() {}") == [.unmatchedBrace])
    }

    @Test("malformed declarations and statements", arguments: [
        ("let x = 1", ErrorCode.expected(what: .declaration, found: .token("let"))),
        ("func f() -> Int", .expected(what: .blockOpen, found: .endOfFile)),
        ("func f() { let x }", .expected(what: .bindingValue, found: .token("}"))),
        ("func f() { copy }", .expected(what: .copiedName, found: .token("}"))),
    ])
    func malformed(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }
}
