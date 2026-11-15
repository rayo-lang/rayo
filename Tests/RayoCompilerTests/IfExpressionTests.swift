import Testing

struct IfExpressionTests {
    @Test("a 'let' that takes the 'if' moves the local its branch ends in, and an argument borrows it", arguments: [
        ("let y = if c { x } else { 2 }\nprint(y)\nprint(x)", ["6:7: error[E0303]: 'x' may have been moved"]),
        ("let y = if c { x } else { copy x }\nprint(y)\nprint(x)", ["6:7: error[E0303]: 'x' may have been moved"]),
        ("let y = if c { x } else { x }\nprint(y)\nprint(x)", ["6:7: error[E0302]: 'x' was moved"]),
        ("print(if c { x } else { 2 })\nprint(x)", []),
        ("let y = if c { copy x } else { 2 }\nprint(y)\nprint(x)", []),
    ])
    func moves(body: String, expected: [String]) {
        #expect(errorLines(inMain: "let c = true\nlet x = 1\n\(body)") == expected)
    }

    @Test func `a local that takes an 'if' is assigned once, so a value no code reads is one error`() {
        #expect(errorLines(inMain: "let c = true\nlet y = if c { 1 } else { 2 }") == [
            "3:5: error[E0308]: the value assigned to 'y' is never read",
        ])
    }
}
