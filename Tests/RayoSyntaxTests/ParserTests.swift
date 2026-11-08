import RayoSource
import Testing
@testable import RayoSyntax

/// Parses `source` as a whole file that must have no errors, and dumps it.
private func file(_ source: String) -> String {
    let (parsed, diagnostics) = Parser.parse(source)
    #expect(diagnostics.map(\.description) == [])
    return parsed.dump
}

/// Parses `source` as a function's body that must have no errors, and dumps its statements.
private func body(_ source: String) -> String {
    let (parsed, diagnostics) = Parser.parse("func t() {\n\(source)\n}")
    #expect(diagnostics.map(\.description) == [])
    guard parsed.functions.count == 1, let function = parsed.functions.first else {
        Issue.record("expected one function, got \(parsed.dump)")
        return ""
    }
    return function.body.statements.map(\.dump).joined(separator: "; ")
}

private func errors(_ source: String) -> [String] {
    Parser.parse(source).diagnostics.map(\.description)
}

struct ExpressionTests {
    @Test("precedence and associativity", arguments: [
        ("a + b * c", "(+ a (* b c))"),
        ("a * b + c", "(+ (* a b) c)"),
        ("a - b - c", "(- (- a b) c)"),
        ("a || b && c == d", "(|| a (&& b (== c d)))"),
        ("a < b == c", "(== (< a b) c)"),
        ("a + b < c * d", "(< (+ a b) (* c d))"),
        ("(a + b) * c", "(* (+ a b) c)"),
        ("a % b / c", "(/ (% a b) c)"),
        ("a >= b", "(>= a b)"),
        ("a <= b != c > d", "(> (!= (<= a b) c) d)"),
    ])
    func precedence(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("prefix operators and 'copy' bind tighter than binary operators", arguments: [
        ("-a * b", "(* (- a) b)"),
        ("!x && y", "(&& (! x) y)"),
        ("copy a + 1", "(+ (copy a) 1)"),
        ("- -a", "(- (- a))"),
        ("-9223372036854775808", "-9223372036854775808"),
        ("-(5)", "(- 5)"),
    ])
    func prefix(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("calls", arguments: [
        ("f()", "(call f)"),
        ("f(a, b)", "(call f a b)"),
        ("f(\n  a,\n  b,\n)", "(call f a b)"),
        ("f(copy y, g(1))", "(call f (copy y) (call g 1))"),
    ])
    func calls(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("a line that ends in a comparison '>' continues")
    func greaterContinues() {
        #expect(body("let ok = a >\n    b") == "(let ok (> a b))")
        #expect(body("let ok = a >=\n    b") == "(let ok (>= a b))")
    }
}

struct StatementTests {
    @Test("bindings", arguments: [
        ("let x = 1", "(let x 1)"),
        ("var x: Int = 1", "(var x: Int 1)"),
        ("let e = take()", "(let e (call take))"),
        ("let all = enemies", "(let all enemies)"),
    ])
    func bindings(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("assignments", arguments: [
        ("x = 1", "(= x 1)"),
        ("x *= 2; x /= 3; x %= 4; x += 5; x -= 6", "(*= x 2); (/= x 3); (%= x 4); (+= x 5); (-= x 6)"),
    ])
    func assignments(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("control flow", arguments: [
        ("if a { x = 1 } else if b { x = 2 } else { x = 3 }",
         "(if a {(= x 1)} else {(if b {(= x 2)} else {(= x 3)})})"),
        ("if a { b() }\nelse { c() }", "(if a {(call b)} else {(call c)})"),
        ("while i < n { i += 1; if done { break } else { continue } }",
         "(while (< i n) {(+= i 1); (if done {(break)} else {(continue)})})"),
    ])
    func controlFlow(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("newlines end statements, and a line that starts with '-' starts one")
    func statementBoundaries() {
        #expect(body("let a = b\n-c") == "(let a b); (- c)")
        #expect(body("let total = base +\n    bonus * 2") == "(let total (+ base (* bonus 2)))")
    }
}

struct DeclarationTests {
    @Test("a function has a name, '()', an optional result type and a body", arguments: [
        ("func f() {}", "(func f() {})"),
        ("func f() -> Int { 1 }", "(func f() -> Int {1})"),
        ("func f() -> () {}", "(func f() -> () {})"),
    ])
    func functions(source: String, expected: String) {
        #expect(file(source) == expected)
    }

    @Test("declarations are separated by newlines")
    func separated() {
        #expect(file("func a() {}\n\nfunc b() -> Int { 1 }") == "(func a() {})\n(func b() -> Int {1})")
        #expect(errors("func a() {} func b() {}") ==
            ["1:13: error: expected a newline or ';' after the declaration, found 'func'"])
    }
}

struct ErrorTests {
    @Test("the parser recovers at the next statement and reports every error")
    func recovery() {
        let source = """
            func f() {
                let = 1
                let y = 2
                x = )
            }
            func g() {}
            """
        let (parsed, diagnostics) = Parser.parse(source)
        #expect(diagnostics.map(\.description) == [
            "2:9: error: expected a name to bind, found '='",
            "4:9: error: expected an expression, found ')'",
        ])
        #expect(parsed.dump == "(func f() {(let y 2)})\n(func g() {})")
    }

    @Test("the lexer's and the parser's errors come in source order")
    func sourceOrder() {
        #expect(errors("func f() {\n    let = 1\n    let s = \"x\"\n}") == [
            "2:9: error: expected a name to bind, found '='",
            "3:13: error: string literals aren't supported yet",
        ])
    }

    @Test("an unclosed block is reported at the end of the file")
    func unclosed() {
        #expect(errors("func f() {\n    x = 1\n") == ["3:1: error: expected '}' to close the block, found the end of the file"])
    }

    @Test("a stray '}' is reported and skipped")
    func strayBrace() {
        #expect(errors("}\nfunc f() {}") == ["1:1: error: unmatched '}'"])
    }

    @Test("malformed declarations and statements", arguments: [
        ("let x = 1", "1:1: error: expected 'func' to begin a declaration, found 'let'"),
        ("func f() -> Int", "1:16: error: expected '{' to begin a block, found the end of the file"),
        ("func f() { let x }", "1:18: error: expected '=' and a value, found '}'"),
        ("func f() { copy }", "1:17: error: expected a name after 'copy', found '}'"),
    ])
    func malformed(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }
}

struct SyntaxTreeTests {
    @Test("a node's range covers its source text")
    func ranges() throws {
        let source = "func f() {\n    let x = foo(a, b) + -d\n    run(n)\n    (a + b)\n    let c = copy x\n}"
        let (parsed, _) = Parser.parse(source)
        let function = try #require(parsed.functions.first)
        let statements = function.body.statements
        #expect(text(function.range, in: source) == source)
        #expect(text(statements[0].range, in: source) == "let x = foo(a, b) + -d")
        if case .binding(let binding) = statements[0].kind {
            #expect(text(binding.value.range, in: source) == "foo(a, b) + -d")
        } else {
            Issue.record("expected a binding")
        }
        #expect(text(statements[1].range, in: source) == "run(n)")
        #expect(text(statements[2].range, in: source) == "(a + b)")
        if case .binding(let binding) = statements[3].kind {
            #expect(text(binding.value.range, in: source) == "copy x")
        } else {
            Issue.record("expected a binding")
        }
    }
}

private func text(_ range: SourceRange, in source: String) -> String {
    String(decoding: Array(source.utf8)[range.start.offset..<range.end.offset], as: UTF8.self)
}
