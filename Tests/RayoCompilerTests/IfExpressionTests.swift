import Testing
import RayoDiagnostics

struct IfExpressionTests {
    @Test("an 'if' used for its value needs an 'else' on every path, reported at the 'if' that lacks one", arguments: [
        ("let y = if c { 1 }", "3:9: error[E0253]: an 'if' used for its value needs an 'else'"),
        ("let y = if c { 1 } else if !c { 2 }", "3:25: error[E0253]: an 'if' used for its value needs an 'else'"),
        ("print(if c { 1 })", "3:7: error[E0253]: an 'if' used for its value needs an 'else'"),
    ])
    func needsElse(body: String, expected: String) {
        #expect(errorLines(inMain: "let c = true\n\(body)") == [expected])
    }

    @Test("where the position expects no type, a branch of another type than the first is an error that names both",
          arguments: [
        ("let y = if c { 1 } else { true }",
         "3:27: error[E0254]: the 'if' gives Int in one branch and Bool in another"),
        ("let y = if c { true } else if !c { 1 } else { false }",
         "3:36: error[E0254]: the 'if' gives Bool in one branch and Int in another"),
        ("let y = if c { } else { 1 }", "3:25: error[E0254]: the 'if' gives Void in one branch and Int in another"),
        ("let y = (if c { 1 } else { c }) + 1",
         "3:28: error[E0254]: the 'if' gives Int in one branch and Bool in another"),
    ])
    func branchesDiffer(body: String, expected: String) {
        #expect(errorLines(inMain: "let c = true\n\(body)") == [expected])
    }

    @Test("where the position expects a type, each branch of another type is an error at the branch", arguments: [
        ("let y: Int = if c { true } else { false }", [
            "3:21: error[E0213]: expected Int, found Bool", "3:35: error[E0213]: expected Int, found Bool",
        ]),
        ("show(if c { 1 } else { true })", ["3:24: error[E0213]: expected Int, found Bool"]),
        ("var y = 1\nprint(y)\ny = if c { true } else { 2 }", ["5:12: error[E0213]: expected Int, found Bool"]),
        ("let p = Point(x: if c { 1 } else { true })\nprint(p.x)",
         ["3:36: error[E0248]: the field 'x' takes Int, found Bool"]),
    ])
    func expectedType(body: String, expected: [String]) {
        let source = "func main() {\nlet c = true\n\(body)\n}\nstruct Point(var x: Int)\nfunc show(_ n: Int) {}"
        #expect(diagnostics(source).map(\.description) == expected)
    }

    @Test func `a 'return' expects the function's result type of each branch`() {
        let source = "func main() {}\nfunc f(_ c: Bool) -> Int {\nreturn if c { 1 } else { false }\n}"
        #expect(diagnostics(source).map(\.description) == ["3:26: error[E0213]: expected Int, found Bool"])
    }

    @Test("a branch that ends in 'return', 'break' or 'continue' fits the type of the other", arguments: [
        "let y = if c { return } else { 1 }\nprint(y)",
        "let y: Bool = if c { true } else { return }\nprint(y)",
        "while true {\nlet y = if c { break } else { 1 }\nprint(y)\n}",
        "while c {\nprint(if c { continue } else { true })\n}",
        "let y = if c { if !c { return } else { return } } else { 1 }\nprint(y)",
        "let y = if c { let z: Int = if !c { return } else { return } } else { 1 }\nprint(y)",
        "show(if c { return } else { return })",
    ])
    func leavingBranches(body: String) {
        #expect(errors("func main() {\nlet c = true\n\(body)\n}\nfunc show(_ n: Int) {}") == [])
    }

    @Test("an 'if' that every branch leaves has no value where the position expects no type", arguments: [
        ("let y = if c { return } else { return }", "3:9"),
        ("print(if c { return } else { return })", "3:7"),
        ("while true {\nprint(if c { break } else { break })\n}", "4:7"),
    ])
    func everyBranchLeaves(body: String, position: String) {
        #expect(errorLines(inMain: "let c = true\n\(body)") == [
            "\(position): error[E0255]: no branch of the 'if' runs to its end, so the 'if' has no value",
        ])
    }

    @Test func `code after an 'if' that every branch leaves can't run, so it needs no 'return'`() {
        let function = "func f(_ c: Bool) -> Int {\nprint(0)\nshow(if c { return 1 } else { return 2 })\n}"
        #expect(errors("func main() {}\n\(function)\nfunc show(_ n: Int) {}") == [])
    }

    @Test func `a 'break' in a branch of an 'if' leaves the loop, so code after the loop can run`() {
        let source = "func main() {}\nfunc f(_ c: Bool) -> Int {\nwhile true {\nlet y = if c { break } else { 1 }\n}\n}"
        #expect(diagnostics(source).map(\.description) == [
            "6:1: error[E0226]: 'f(_: Bool)' can reach its end without returning a value",
        ])
    }

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

    @Test func `as a statement, an 'if''s branches needn't agree, and each value they leave unused is reported`() {
        #expect(errorLines(inMain: "let c = true\nif c { 1 } else { true }") == [
            "3:8: error[E0235]: the Int value isn't used", "3:19: error[E0235]: the Bool value isn't used",
        ])
    }
}
