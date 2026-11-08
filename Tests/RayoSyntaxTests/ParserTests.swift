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

    @Test("prefix operators bind tighter than binary ones, and postfix ones tighter still", arguments: [
        ("-a * b", "(* (- a) b)"),
        ("!x.ready", "(! (. x ready))"),
        ("&x.items[1]", "(& (index (. x items) 1))"),
        ("copy a.b + 1", "(+ (copy (. a b)) 1)"),
        ("consume a", "(consume a)"),
        ("- -a", "(- (- a))"),
        ("-9223372036854775808", "-9223372036854775808"),
        ("-(5)", "(- 5)"),
        ("-5.bitWidth", "(- (. 5 bitWidth))"),
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
        ("let e = list.take()", "(let e (call (. list take)))"),
        ("var e: Enemy", "(var e: Enemy)"),
        ("let all = enemies", "(let all enemies)"),
        ("let seen = borrow enemies[0]", "(let seen (borrow (index enemies 0)))"),
        ("let n = borrow -x.count", "(let n (borrow (- (. x count))))"),
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

    @Test("what the subset doesn't have yet is reported as such", arguments: [
        ("func f() { let a = 1, b = 2 }", "1:21: error: more than one binding in a declaration isn't supported yet"),
        ("func f() { for x in xs {} }", "1:24: error: expected '..<': the one loop supported so far is 'for i in a..<b', found '{'"),
        ("func f() { x <<= 1 }", "1:14: error: '<<=' isn't supported yet"),
        ("func f() { let y = a | b }", "1:22: error: '|' isn't supported yet"),
        ("func f() { if let x = y {} }", "1:15: error: a binding condition isn't supported yet"),
        ("func f() { let y = x? }", "1:21: error: optional chaining isn't supported yet"),
        ("func f() { let y = x! }", "1:21: error: force unwrapping isn't supported yet"),
        ("func f() { let r = 0..<n }", "1:21: error: '..<' isn't supported yet"),
        ("func f() { let y = if a { 1 } else { 2 } }", "1:20: error: 'if' as an expression isn't supported yet"),
        ("func f() { let y = when x {} }", "1:20: error: 'when' as an expression isn't supported yet"),
        ("func f() { do {} catch {} }", "1:18: error: 'catch' isn't supported yet"),
        ("func f() { if a, b {} }", "1:16: error: a condition list isn't supported yet"),
        ("func f() { let t = (a, b) }", "1:22: error: a tuple isn't supported yet"),
        ("func f() { let t = () }", "1:20: error: the empty tuple isn't supported yet"),
        ("func f() { let y = x ?? z }", "1:22: error: '??' isn't supported yet"),
        ("func f() { let x = borrow a ?? b }", "1:29: error: '??' isn't supported yet"),
        ("func f() { let x = borrow a, y = b }", "1:28: error: more than one binding in a declaration isn't supported yet"),
    ])
    func unsupported(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }

    @Test("malformed declarations, types and statements", arguments: [
        ("let x = 1", "1:1: error: expected 'func' to begin a declaration, found 'let'"),
        ("func f() -> Int", "1:16: error: expected '{' to begin a block, found the end of the file"),
        ("func f() { owned let x = 1 }",
         "1:12: error: a declaration takes its value without 'owned'; write 'borrow' after '=' to borrow instead"),
        ("func f() { owned var x = y }", "1:12: error: a declaration takes its value without 'owned'"),
        ("func f() { if owned let x = y {} }", "1:15: error: a binding condition isn't supported yet"),
        ("func f() { if owned x {} }", "1:15: error: expected an expression, found 'owned'"),
        ("func f() { var x = borrow y }", "1:20: error: a 'var' can't borrow shared; write 'let', or '&' to lend the place for change"),
        ("func f() { var x: Int = borrow y }",
         "1:25: error: a 'var' can't borrow shared; write 'let', or '&' to lend the place for change"),
        ("func f() { let x = borrow a + 1 }", "1:29: error: a borrowing initializer ends after the place it borrows, found '+'"),
        ("func f() { let x = borrow a >= b }",
         "1:29: error: a borrowing initializer ends after the place it borrows, found '>='"),
        ("func f() { g(borrow a) }", "1:14: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { borrow a = 1 }", "1:12: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { return borrow a }", "1:19: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { let x = copy borrow a }",
         "1:25: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { let x = borrow borrow a }",
         "1:27: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { let x = (borrow a) }", "1:21: error: 'borrow' is written only to begin the initializer of a local 'let'"),
        ("func f() { for i 0..<n {} }", "1:18: error: expected 'in' after the loop variable, found '0'"),
        ("func f() { x.1 }", "1:14: error: expected a member name after '.', found '1'"),
    ])
    func malformed(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }
}

struct SyntaxTreeTests {
    @Test("a node's range covers its source text")
    func ranges() throws {
        let source = "func f() {\n    let x = foo(a, b).c + -d\n    run(n)\n    (a + b)\n    let s = borrow v.w[0]\n}"
        let (parsed, _) = Parser.parse(source)
        let function = try #require(parsed.functions.first)
        let statements = function.body.statements
        #expect(text(function.range, in: source) == source)
        #expect(text(statements[0].range, in: source) == "let x = foo(a, b).c + -d")
        if case .binding(let binding) = statements[0].kind, let value = binding.value {
            #expect(text(value.range, in: source) == "foo(a, b).c + -d")
        } else {
            Issue.record("expected a binding with a value")
        }
        #expect(text(statements[1].range, in: source) == "run(n)")
        #expect(text(statements[2].range, in: source) == "(a + b)")
        if case .binding(let binding) = statements[3].kind, let value = binding.value {
            #expect(text(value.range, in: source) == "borrow v.w[0]")
        } else {
            Issue.record("expected a borrowing binding")
        }
    }

    @Test("every expression in a file has its own id")
    func uniqueIDs() {
        let source = """
            func g() -> Int { h(copy y, by: a + y)[0] }
            func k() {
                var v = make(capacity: (2))
                let first = borrow v[0]
                if v.isEmpty { while -v.count > 0 { v.append(copy x) } }
                for i in 0..<n { v[i] = consume w; each(v, [1, 2]) }
            }
            """
        let (parsed, diagnostics) = Parser.parse(source)
        #expect(diagnostics.map(\.description) == [])
        let ids = expressionIDs(in: parsed)
        #expect(ids.count > 20)
        #expect(Set(ids).count == ids.count)
    }

    @Test("a member name may be a keyword")
    func keywordMember() {
        #expect(body("x.init") == "(. x init)")
    }
}

private func text(_ range: SourceRange, in source: String) -> String {
    String(decoding: Array(source.utf8)[range.start.offset..<range.end.offset], as: UTF8.self)
}

private func expressionIDs(in file: SourceFile) -> [ExprID] {
    var ids: [ExprID] = []
    func visit(_ expr: Expr) {
        ids.append(expr.id)
        switch expr.kind {
        case .intLiteral, .negativeIntLiteral, .boolLiteral, .name, .selfRef:
            break
        case .member(let base, _, _):
            visit(base)
        case .index(let base, let arguments), .call(let base, let arguments):
            visit(base)
            arguments.forEach { visit($0.value) }
        case .unary(_, let operand), .lend(let operand), .copy(let operand), .consume(let operand),
             .borrow(let operand):
            visit(operand)
        case .binary(_, let left, let right):
            visit(left)
            visit(right)
        case .arrayLiteral(let elements):
            elements.forEach(visit)
        }
    }
    func visit(_ block: Block) {
        for statement in block.statements {
            switch statement.kind {
            case .binding(let binding):
                binding.value.map(visit)
            case .assign(let target, _, let value):
                visit(target)
                visit(value)
            case .expression(let expr):
                visit(expr)
            case .ifStmt(let condition, let then, let otherwise):
                visit(condition)
                visit(then)
                otherwise.map(visit)
            case .whileStmt(let condition, let body):
                visit(condition)
                visit(body)
            case .forRange(_, _, let lower, let upper, let body):
                visit(lower)
                visit(upper)
                visit(body)
            case .returnStmt(let value):
                value.map(visit)
            case .breakStmt, .continueStmt:
                break
            case .doBlock(let block):
                visit(block)
            }
        }
    }
    for function in file.functions { visit(function.body) }
    return ids
}
