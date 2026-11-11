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
            .missingBindingName(found: .token("=")), .missingExpression(found: .token(")")),
        ])
    }

    @Test("a declaration whose header fails is skipped, and the parser goes on at the next declaration")
    func declarationRecovery() {
        #expect(errors("func f(x) {\n    print(1)\n}\nfunc g() { copy }") == [
            .missingParameterType(found: .token(")")), .missingCopiedName(found: .token("}")),
        ])
    }

    @Test("declarations are separated by newlines or ';'")
    func separated() {
        #expect(errors("func a() {}\n\nfunc b() -> Int { 1 }; func c() {}") == [])
        #expect(errors("func a() {} func b() {}") == [.unendedDeclaration(found: .token("func"))])
    }

    @Test("the lexer's and the parser's errors come in source order")
    func sourceOrder() {
        #expect(errors("func f() {\n    let = 1\n    let s = 0x\n}") == [
            .missingBindingName(found: .token("=")), .missingDigits,
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
        #expect(errors("func f() {\n    x = 1\n") == [.unclosedBlock(found: .endOfFile)])
    }

    @Test("a stray '}' is reported and skipped")
    func strayBrace() {
        #expect(errors("}\nfunc f() {}") == [.unmatchedBrace])
    }

    @Test func `'return' takes a value on its own line, and a 'return' that ends its line takes none`() {
        // A `return` with its value on its line, one that ends its line before a value, and one in an `if` parse.
        let source = "func f() -> Int { return 1 }\nfunc g() {\n    return\n    1\n}\n"
            + "func h() { if true { return } }"
        #expect(errors(source) == [])

        // A value that doesn't end the statement, a missing value, and `return` as a name are each an error.
        #expect(errors("func f() { return 1 2 }") == [.unendedStatement(found: .token("2"))])
        #expect(errors("func f() { return ) }") == [.missingExpression(found: .token(")"))])
        #expect(errors("func f() { let return = 1 }") == [.missingBindingName(found: .token("return"))])
    }

    @Test("parameters and arguments are separated by commas, may end in one, and may carry keyword labels")
    func parameters() {
        #expect(errors("func f(_ a: Int, in b: Bool, c: Int,) { f(1, in: true, c: 2,) }") == [])
        #expect(errors("func f(if x: Int) { f(if: 1) }") == [])
        #expect(errors("func f(a: Int,, b: Int) {}") == [.missingParameterName(found: .token(","))])
        #expect(errors("func f(a b c: Int) {}") == [.missingParameterType(found: .token("c"))])
    }

    @Test("a declaration binds one name or several, separated by commas, each with or without a type and a value",
          arguments: [
        "let x", "var x: Int", "let x = 1", "let lo: Int, hi: Int", "var a = 1, b: Bool, c: Int = 2, d",
    ])
    func declarations(declaration: String) {
        #expect(errors("func f() {\n    \(declaration)\n    \(declaration); print(1)\n}") == [])
    }

    @Test("a declaration's bindings are each checked for a name", arguments: [
        ("func f() { let x, }", ErrorCode.missingBindingName(found: .token("}"))),
        ("func f() { var x = 1, = 2 }", .missingBindingName(found: .token("="))),
        ("func f() { let x = }", .missingExpression(found: .token("}"))),
    ])
    func malformedBindings(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test("malformed declarations and statements", arguments: [
        ("let x = 1", ErrorCode.missingFunc(found: .token("let"))),
        ("func f() -> Int", .missingBlock(found: .endOfFile)),
        ("func f() { copy }", .missingCopiedName(found: .token("}"))),
        ("func f() { _ = = 1 }", .missingExpression(found: .token("="))),
    ])
    func malformed(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }
}
