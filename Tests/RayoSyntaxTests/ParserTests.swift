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
    guard parsed.declarations.count == 1, case .function(let function) = parsed.declarations[0] else {
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

    @Test("prefix operators bind tighter than binary ones, and postfix ones tighter still", arguments: [
        ("-a * b", "(* (- a) b)"),
        ("!x.ready", "(! (. x ready))"),
        ("&x.items[1]", "(& (index (. x items) 1))"),
        ("copy a.b + 1", "(+ (copy (. a b)) 1)"),
        ("consume a", "(consume a)"),
        ("- -a", "(- (- a))"),
        ("-9223372036854775808", "(- 9223372036854775808)"),
    ])
    func prefix(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("calls, members, indexing and labels", arguments: [
        ("f()", "(call f)"),
        ("f(a, by: b)", "(call f a by:b)"),
        ("f(in: s, copy: c)", "(call f in:s copy:c)"),
        ("x.hit(by: 3).hp", "(. (call (. x hit) by:3) hp)"),
        ("a[i][j]", "(index (index a i) j)"),
        ("f(\n  a,\n  b,\n)", "(call f a b)"),
        ("f(&x, copy y)", "(call f (& x) (copy y))"),
        ("Point(x: 1, y: 2)", "(call Point x:1 y:2)"),
        ("[1, 2, 3,]", "(array 1 2 3)"),
        ("[]", "(array)"),
        ("true && false", "(&& true false)"),
        ("self.hp", "(. self hp)"),
    ])
    func postfix(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("'<' opens generic arguments only when the token after '>' can follow them", arguments: [
        ("List<Int>()", "(call List<Int>)"),
        ("List<List<Int>>(capacity: 3)", "(call List<List<Int>> capacity:3)"),
        ("f(a < b, c > (d))", "(call f (call a<b, c> d))"),
        ("f(a < b, (c > d))", "(call f (< a b) (> c d))"),
        ("a < b", "(< a b)"),
        ("a < b > c", "(> (< a b) c)"),
        ("T == List<Int> || x", "(|| (== T List<Int>) x)"),
        ("Box<[4 of Int]>.make()", "(call (. Box<[4 of Int]> make))"),
        ("List<Int,>()", "(call List<Int>)"),
    ])
    func genericArguments(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("a line that ends in a comparison '>' continues")
    func greaterContinues() {
        #expect(body("let ok = a >\n    b") == "(let ok (> a b))")
        #expect(body("let ok = a >=\n    b") == "(let ok (>= a b))")
    }

    @Test("a '>' that closes generic arguments ends the line")
    func greaterClosesLine() {
        #expect(body("let xs: List<Int>\nf()") == "(let xs: List<Int>); (call f)")
    }
}

struct ClosureTests {
    @Test("signatures", arguments: [
        ("let f = { [move level] in start(level) }", "(let f (closure [move level] {(call start level)}))"),
        ("let f = { [copy id, move self] in log(id) }", "(let f (closure [copy id, move self] {(call log id)}))"),
        ("let f = { a, b in a + b }", "(let f (closure (a, b) {(+ a b)}))"),
        ("let f = { (a: Int, b: mutable Int) -> Int in a }", "(let f (closure (a: Int, b: mutable Int) -> Int {a}))"),
        ("let f = { -> Int in 1 }", "(let f (closure -> Int {1}))"),
        ("let f = { $0.hp > 0 }", "(let f (closure {(> (. $0 hp) 0)}))"),
        ("let f = { x }", "(let f (closure {x}))"),
        ("let f = { [copy x] }", "(let f (closure {(array (copy x))}))"),
        ("let f = { (a + b) }", "(let f (closure {(+ a b)}))"),
        ("let f = {\n  hits += 1\n  log(hits)\n}", "(let f (closure {(+= hits 1); (call log hits)}))"),
    ])
    func signatures(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("trailing closures", arguments: [
        ("each(xs) { e in log(e) }", "(call each xs (closure (e) {(call log e)}))"),
        ("run { tick() }", "(call run (closure {(call tick)}))"),
        ("xs.forEach { log($0) }", "(call (. xs forEach) (closure {(call log $0)}))"),
        ("pair(a) { x } { y }", "(call pair a (closure {x}) (closure {y}))"),
    ])
    func trailing(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("no trailing closures where a statement's block follows", arguments: [
        ("if xs.isEmpty { reset() }", "(if (. xs isEmpty) {(call reset)})"),
        ("while ok(x) { step() }", "(while (call ok x) {(call step)})"),
        ("for i in 0..<n { use(i) }", "(for i 0 n {(call use i)})"),
        ("while xs.any({ $0.alive }) { step() }",
         "(while (call (. xs any) (closure {(. $0 alive)})) {(call step)})"),
        ("if f(g { 1 }) { step() }", "(if (call f (call g (closure {1}))) {(call step)})"),
    ])
    func condition(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("a closure literal used as a statement is an error")
    func closureStatement() {
        #expect(errors("func t() {\n    { reset() }\n}") ==
            ["2:5: error: this closure would never run; 'do { … }' groups statements"])
        #expect(body("do { reset() }") == "(do {(call reset)})")
    }
}

struct StatementTests {
    @Test("bindings", arguments: [
        ("let x = 1", "(let x 1)"),
        ("var x: Int = 1", "(var x: Int 1)"),
        ("owned let e = list.take()", "(owned let e (call (. list take)))"),
        ("owned var e: Enemy", "(owned var e: Enemy)"),
        ("var b: Box<Int>= a", "(var b: Box<Int> a)"),
        ("var a: [3 of Int] = [1, 2, 3]", "(var a: [3 of Int] (array 1 2 3))"),
        ("var t = &world.enemies", "(var t (& (. world enemies)))"),
    ])
    func bindings(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("assignments", arguments: [
        ("x = 1", "(= x 1)"),
        ("a[0] = a[1] + 1", "(= (index a 0) (+ (index a 1) 1))"),
        ("e.hp -= damage", "(-= (. e hp) damage)"),
        ("x *= 2; x /= 3; x %= 4; x += 5", "(*= x 2); (/= x 3); (%= x 4); (+= x 5)"),
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
        ("for i in a + 1..<n * 2 { }", "(for i (+ a 1) (* n 2) {})"),
        ("return", "(return)"),
        ("return x + 1", "(return (+ x 1))"),
        ("if x { return }", "(if x {(return)})"),
    ])
    func controlFlow(source: String, expected: String) {
        #expect(body(source) == expected)
    }

    @Test("newlines end statements, and a line that starts with '-' starts one")
    func statementBoundaries() {
        #expect(body("let a = b\n-c") == "(let a b); (- c)")
        #expect(body("let n = xs\n    .count") == "(let n (. xs count))")
        #expect(body("let total = base +\n    bonus * 2") == "(let total (+ base (* bonus 2)))")
    }
}

struct DeclarationTests {
    @Test("a struct with fields, conformances, methods and a deinit")
    func structure() {
        let source = """
            struct Enemy(var hp: Int, let id: Int = 0): ~Copyable, Scoped {
                func alive() -> Bool { hp > 0 }
                mutating func hit(by damage: Int) { hp -= damage }
                consuming func finish() -> Int { id }
                deinit { log(id) }
            }
            """
        #expect(file(source) == """
            (struct Enemy(var hp: Int, let id: Int = 0): ~Copyable, Scoped
              (func alive() -> Bool {(> hp 0)})
              (mutating func hit(by damage: Int) {(-= hp damage)})
              (consuming func finish() -> Int {id})
              (deinit {(call log id)}))
            """)
    }

    @Test("a struct with no body, and one with no fields")
    func plainStructs() {
        #expect(file("struct Point(var x: Int, var y: Int)\nstruct Marker {}") ==
            "(struct Point(var x: Int, var y: Int))\n(struct Marker)")
    }

    @Test("parameter labels and conventions")
    func parameters() {
        #expect(file("func move(_ e: owned Enemy, into list: mutable List<Enemy>, in s: Span<Int>, n: Int) {}") ==
            "(func move(_ e: owned Enemy, into list: mutable List<Enemy>, in s: Span<Int>, n: Int) {})")
    }

    @Test("types", arguments: [
        ("mutating (keep Span<Int>, mutable Int) -> Void", "mutating (keep Span<Int>, mutable Int) -> Void"),
        ("some consuming () -> Int", "some consuming () -> Int"),
        ("(Int) -> (Int) -> Bool", "(Int) -> (Int) -> Bool"),
        ("Closure<() -> Void>", "Closure<() -> Void>"),
        ("[4 of [2 of Int]]", "[4 of [2 of Int]]"),
        ("()", "()"),
        ("(Int)", "Int"),
        ("(keep owned MutableSpan<Int>) -> Void", "(keep owned MutableSpan<Int>) -> Void"),
        ("(keep) -> Void", "(keep) -> Void"),
    ])
    func types(source: String, expected: String) {
        #expect(file("func f(_ x: \(source)) {}") == "(func f(_ x: \(expected)) {})")
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

    @Test("a second deinit is reported at its keyword, in source order")
    func secondDeinit() {
        #expect(errors("struct S {\n    deinit {}\n    deinit {}\n    func f() { let = 1 }\n}") == [
            "3:5: error: a type declares at most one 'deinit'",
            "4:20: error: expected a name to bind, found '='",
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

    @Test("what the subset doesn't have yet is reported as such", arguments: [
        ("func f<T>(_ x: T) {}", "1:7: error: a generic function isn't supported yet"),
        ("func f() throws {}", "1:10: error: 'throws' isn't supported yet"),
        ("func f(_ x: Int = 1) {}", "1:17: error: a default argument isn't supported yet"),
        ("func f(_ x: Int?) {}", "1:16: error: an optional type isn't supported yet"),
        ("func f(_ x: (Int, Int)) {}", "1:13: error: a tuple type isn't supported yet"),
        ("func f() { let a = 1, b = 2 }", "1:21: error: more than one binding in a declaration isn't supported yet"),
        ("func f() { for x in xs {} }", "1:24: error: expected '..<': the one loop supported so far is 'for i in a..<b', found '{'"),
        ("func f() { x <<= 1 }", "1:14: error: '<<=' isn't supported yet"),
        ("func f() { let y = a | b }", "1:22: error: '|' isn't supported yet"),
        ("func f() { if let x = y {} }", "1:15: error: a binding condition isn't supported yet"),
        ("func f() { let y = x? }", "1:21: error: optional chaining isn't supported yet"),
        ("func f() { let y = x! }", "1:21: error: force unwrapping isn't supported yet"),
        ("func f() { let r = 0..<n }", "1:21: error: '..<' isn't supported yet"),
        ("func f() { let y = if a { 1 } else { 2 } }", "1:20: error: 'if' as an expression isn't supported yet"),
    ])
    func unsupported(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }
}
