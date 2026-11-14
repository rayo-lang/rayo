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
        let failed = try #require(file.failedDeclarations.first)
        #expect(file.failedDeclarations.count == 1)
        #expect((failed.kind, failed.name) == (kind, name))
        #expect(covered(by: failed, in: text) == coveredText)
        // The declaration before it is parsed as usual.
        #expect(file.functions.map(\.name) == ["g"])
    }

    @Test func `text that begins no declaration leaves nothing in the tree`() {
        let file = Parser.parse("let x = 1\nfunc g() {}").file
        #expect(file.failedDeclarations.isEmpty)
        #expect(file.functions.map(\.name) == ["g"])
    }

    @Test(arguments: ["let = 1", "print(1) 2", "x = )"])
    func `a statement that fails to parse leaves an error statement in its place`(statement: String) throws {
        let file = Parser.parse("func f() {\n    print(0)\n    \(statement)\n    print(2)\n}").file
        let statements = try #require(file.functions.first).body.statements
        try #require(statements.count == 3)
        guard case .error = statements[1].kind else {
            Issue.record("expected an error statement, found \(statements[1].kind)")
            return
        }
    }
}
