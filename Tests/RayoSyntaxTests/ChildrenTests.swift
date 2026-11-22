import Testing
import RayoSyntax

/// The statements of the body of `source`'s one function.
private func statements(of source: String) throws -> [Stmt] {
    guard case .function(let function)? = Parser.parse(source).file.declarations.first else {
        throw ExpectedFunction()
    }
    return function.body.statements
}

private struct ExpectedFunction: Error {}

/// Each of `children` as `source` writes it: an expression as its text, and a block as `{n}`, where `n` counts its
/// statements.
private func summaries(of children: [SyntaxChild], in source: String) -> [String] {
    let bytes = Array(source.utf8)
    return children.map { child in
        switch child {
        case .expression(let expr): text(of: expr, in: bytes)
        case .block(let block): "{\(block.statements.count)}"
        }
    }
}

/// The text that `expr` covers in the source whose bytes are `bytes`.
private func text(of expr: Expr, in bytes: [UInt8]) -> String {
    String(decoding: bytes[expr.range.start.offset..<expr.range.end.offset], as: UTF8.self)
}

struct ChildrenTests {
    @Test(arguments: [
        ("g(a, b[i])", ["g", "a", "b[i]"]),
        ("a.b", ["a"]),
        ("copy a.b", ["a.b"]),
        ("consume a[i]", ["a[i]"]),
        ("-a", ["a"]),
        ("a && b + c", ["a", "b + c"]),
        ("[a, 1]", ["a", "1"]),
        ("if c { 1 } else { a\n    b }", ["c", "{1}", "{2}"]),
        ("if c { 1 }", ["c", "{1}"]),
        ("1", []),
        ("a", []),
        (".zero", []),
    ])
    func `an expression's children are the expressions and blocks it holds, in source order`(
        expression: String, expected: [String],
    ) throws {
        let source = "func f() {\n    _ = \(expression)\n}"
        guard case .drop(let expr) = try statements(of: source)[0].kind else {
            Issue.record("expected '_ = \(expression)' to drop a value")
            return
        }
        #expect(summaries(of: expr.children, in: source) == expected)
    }

    @Test(arguments: [
        ("let a = 1, b, c = d", ["1", "d"]),
        ("a += b", ["a", "b"]),
        ("_ = a", ["a"]),
        ("a", ["a"]),
        ("return a", ["a"]),
        ("return", []),
        ("if c { 1 } else { a\n    b }", ["c", "{1}", "{2}"]),
        ("while c { break }", ["c", "{1}"]),
        ("break", []),
        ("continue", []),
        ("let = 1", []),
    ])
    func `a statement's children are the expressions and blocks it holds, in source order`(
        statement: String, expected: [String],
    ) throws {
        let source = "func f() {\n    \(statement)\n}"
        #expect(summaries(of: try statements(of: source)[0].children, in: source) == expected)
    }
}
