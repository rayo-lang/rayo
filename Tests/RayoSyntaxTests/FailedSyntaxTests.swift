import Testing
import RayoSyntax

/// The text of `source` that the parser's failed declaration `declaration` covers.
private func covered(by declaration: FailedDecl, in source: String) -> String {
    let bytes = Array(source.utf8)
    return String(decoding: bytes[declaration.range.start.offset..<declaration.range.end.offset], as: UTF8.self)
}

struct FailedSyntaxTests {
    @Test(arguments: [
        ("func f(x) {\n    print(1)\n}", FailedDecl.Kind.function, "f" as String?, "func f(x) {\n    print(1)\n}"),
        ("func (", .function, nil, "func ("),
        ("struct S(var x Int)", .structure, "S", "struct S(var x Int)"),
        ("struct", .structure, nil, "struct"),
    ])
    func `a declaration that fails to parse stays in the tree, with its kind and the name it reached`(
        source: String, kind: FailedDecl.Kind, name: String?, coveredText: String,
    ) throws {
        let text = "func g() {}\n" + source
        let file = Parser.parse(text).file
        try #require(file.declarations.count == 2)
        guard case .failed(let failed) = file.declarations[1] else {
            Issue.record("expected a failed declaration, found \(file.declarations[1])")
            return
        }
        #expect((failed.kind, failed.name) == (kind, name))
        #expect(covered(by: failed, in: text) == coveredText)
        // The declaration before it is parsed as usual.
        guard case .function(let function) = file.declarations[0] else {
            Issue.record("expected a function, found \(file.declarations[0])")
            return
        }
        #expect(function.name == "g")
    }

    @Test func `text that begins no declaration leaves nothing in the tree`() {
        let file = Parser.parse("let x = 1\nfunc g() {}").file
        #expect(file.declarations.map(\.name) == ["g"])
    }

    @Test(arguments: ["let = 1", "print(1) 2", "x = )"])
    func `a statement that fails to parse leaves an error statement in its place`(statement: String) throws {
        let file = Parser.parse("func f() {\n    print(0)\n    \(statement)\n    print(2)\n}").file
        guard case .function(let function)? = file.declarations.first else {
            Issue.record("expected a function, found \(file.declarations)")
            return
        }
        let statements = function.body.statements
        try #require(statements.count == 3)
        guard case .error = statements[1].kind else {
            Issue.record("expected an error statement, found \(statements[1].kind)")
            return
        }
    }

    @Test(arguments: [
        ("let a = 3 $ 4", ["a"]), ("var a: Int = (1", ["a"]), ("let a, b = 1 2", ["a", "b"]),
        ("let a, = 1", ["a"]), ("let = 1", []), ("print(1) 2", []), ("if ( {}", []),
    ])
    func `a statement that fails to parse keeps the names its 'let' or 'var' binds before the error`(
        statement: String, names: [String],
    ) throws {
        let file = Parser.parse("func f() {\n    \(statement)\n}").file
        guard case .function(let function)? = file.declarations.first else {
            Issue.record("expected a function, found \(file.declarations)")
            return
        }
        let failed = try #require(function.body.statements.first)
        guard case .error(let boundNames) = failed.kind else {
            Issue.record("expected an error statement, found \(failed.kind)")
            return
        }
        #expect(boundNames == names)
    }
}
