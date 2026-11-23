import Testing
import RayoSyntax

/// The text of `source` that the parser's failed declaration `declaration` covers.
private func covered(by declaration: FailedDecl, in source: String) -> String {
    let bytes = Array(source.utf8)
    return String(decoding: bytes[declaration.range.start.offset..<declaration.range.end.offset], as: UTF8.self)
}

/// The names of the items in a failed declaration's header, with `failed` for each item that failed.
private func names<Item>(of items: [HeaderItem<Item>], _ name: KeyPath<Item, String>) -> [String] {
    items.map { item in
        switch item {
        case .parsed(let parsed): parsed[keyPath: name]
        case .failed: "failed"
        }
    }
}

struct FailedSyntaxTests {
    @Test(arguments: [
        ("func f(x) {\n    print(1)\n}", false, "f" as String?, "func f(x) {\n    print(1)\n}"),
        ("func (", false, nil, "func ("),
        ("struct S(var x Int)", true, "S", "struct S(var x Int)"),
        ("struct", true, nil, "struct"),
    ])
    func `a declaration that fails to parse stays in the tree, with its kind and the name it reached`(
        source: String, declaresType: Bool, name: String?, coveredText: String,
    ) throws {
        let text = "func g() {}\n" + source
        let file = Parser.parse(text).file
        try #require(file.declarations.count == 2)
        guard case .failed(let failed) = file.declarations[1] else {
            Issue.record("expected a failed declaration, found \(file.declarations[1])")
            return
        }
        #expect((file.declarations[1].declaresType, failed.name) == (declaresType, name))
        #expect(covered(by: failed, in: text) == coveredText)
        // The declaration before it is parsed as usual.
        guard case .function(let function) = file.declarations[0] else {
            Issue.record("expected a function, found \(file.declarations[0])")
            return
        }
        #expect(function.name == "g")
    }

    @Test func `a function whose header fails keeps its parameters and its body in the tree`() throws {
        let file = Parser.parse("func f(a: Int, b, c: Bool) -> Int {\n    print(1)\n    copy\n}").file
        guard case .failed(let failed)? = file.declarations.first,
              case .function(let parameters, let result, let body) = failed.parts
        else {
            Issue.record("expected a failed function, found \(file.declarations)")
            return
        }
        #expect(names(of: parameters, \.name) == ["a", "failed", "c"])
        #expect(result?.spelling == "Int")
        let statements = try #require(body).statements
        try #require(statements.count == 2)
        guard case .error = statements[1].kind else {
            Issue.record("expected an error statement, found \(statements[1].kind)")
            return
        }
    }

    @Test func `a struct with a field that fails keeps its other fields and its members in the tree`() {
        let file = Parser.parse("struct S(var a: Int, b: Bool, let c: Int) {\n    func f() {}\n}").file
        guard case .failed(let failed)? = file.declarations.first,
              case .structure(let fields, let members) = failed.parts
        else {
            Issue.record("expected a failed struct, found \(file.declarations)")
            return
        }
        #expect(names(of: fields, \.name) == ["a", "failed", "c"])
        #expect(members.map(\.name) == ["f"])
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
