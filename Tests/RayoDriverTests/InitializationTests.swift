import Testing
import RayoDiagnostics
import RayoDriver

struct InitializationTests {
    @Test("a local declared without a value is given one later, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func lateInitialization(mode: [String]) {
        let source = """
            func main() {
                let lo: Int, hi: Int
                lo = 1
                hi = 2
                var sum: Int
                sum = lo + hi
                sum = sum * 10
                sum += 4
                print(sum)
                print(pick(true))
                print(pick(false))
            }
            func pick(_ first: Bool) -> Int {
                let picked: Int
                if first {
                    picked = 1
                } else {
                    picked = 2
                }
                return picked
            }
            """
        #expect(run(source, options: mode) == RunResult(exitCode: 0, output: "34\n1\n2\n", errors: ""))
    }

    @Test("a local declared without a value needs a type, and the error covers its name", arguments: [
        ("let x", [ErrorCode.missingLocalType(name: "x")], ["x"]),
        ("var a = 1, b", [.missingLocalType(name: "b")], ["b"]),
        ("let x\nprint(x)\nx = 1", [.missingLocalType(name: "x")], ["x"]),
        ("let x: Int8", [.notAType(name: "Int8")], ["Int8"]),
        ("var x: ()", [.voidLocal], ["()"]),
        ("let _: Int", [.underscoreDeclared], ["_"]),
    ])
    func needsType(body: String, expected: [ErrorCode], covered: [String]) {
        #expect(codesAndCoverage(inMain: body) == (expected, covered))
    }

    @Test("each binding of a declaration binds a name, and the type of one that binds '_' is still checked",
          arguments: [
        ("let a = 1, _ = 2", [ErrorCode.underscoreDeclared], ["_"]),
        ("var _: Int, b: Int", [.underscoreDeclared], ["_"]),
        ("let _: Int8", [.underscoreDeclared, .notAType(name: "Int8")], ["_", "Int8"]),
    ])
    func underscoreBinding(body: String, expected: [ErrorCode], covered: [String]) {
        #expect(codesAndCoverage(inMain: body) == (expected, covered))
    }

    @Test("a declaration's bindings are declared in order, so a later one may take an earlier one's value")
    func severalBindings() {
        // A binding may use the one before it.
        #expect(output("let a = 1, b = copy a + 1, c: Int\nc = a + b\nprint(c)") == "3\n")

        // A binding can't use the one after it, which isn't declared yet.
        #expect(errors("func main() {\nlet a = b, b = 1\n}") == [.notDeclared(name: "b")])
    }

    @Test("a local declared without a value and never used is no error")
    func neverUsed() {
        #expect(errors("func main() {\nlet x: Int\nvar y: Bool\n}") == [])
    }

    @Test("a use of a local that nothing has assigned is an error at the use, and the error covers its name",
          arguments: [
        ("let x: Int\nprint(x)", "3:7: error[E0304]: 'x' isn't initialized"),
        ("var x: Int\nx += 1", "3:1: error[E0304]: 'x' isn't initialized"),
        ("let x: Bool\nif x { }", "3:4: error[E0304]: 'x' isn't initialized"),
        ("let x: Int\nlet y = x", "3:9: error[E0304]: 'x' isn't initialized"),
        ("let x: Int\nx = x", "3:5: error[E0304]: 'x' isn't initialized"),
        ("var x: Int\nprint(x)\nprint(x + 1)\nx = 1\nprint(x)", "3:7: error[E0304]: 'x' isn't initialized"),
    ])
    func useBeforeAssignment(body: String, expected: String) {
        #expect(errorLines(inMain: body) == [expected])
    }

    @Test("each local that nothing has assigned is an error of its own")
    func eachLocal() {
        #expect(errorLines(inMain: "let a: Int, b: Int\nprint(a + b)") == [
            "3:7: error[E0304]: 'a' isn't initialized", "3:11: error[E0304]: 'b' isn't initialized",
        ])
    }

    @Test("a local assigned on one path of an 'if' isn't initialized on every path after it",
          arguments: [
        ("if true { x = 1 }", ["4:7: error[E0305]: 'x' isn't initialized on every path"]),
        ("if true { } else { x = 2 }", ["4:7: error[E0305]: 'x' isn't initialized on every path"]),
        ("if true { x = 1 } else { x = 2 }", []),
    ])
    func branches(statement: String, expected: [String]) {
        #expect(errorLines(inMain: "let x: Int\n\(statement)\nprint(x)") == expected)
    }

    @Test("a path that assigns a local and returns leaves the local without a value on the others", arguments: [
        ("if c {\n        x = 1\n        return\n    }", "8:11: error[E0304]: 'x' isn't initialized"),
        ("if c {\n        return\n    }", "7:11: error[E0304]: 'x' isn't initialized"),
    ])
    func returns(statement: String, expected: String) {
        let source = "func main() {}\nfunc f(_ c: Bool) {\n    var x: Int\n    \(statement)\n    print(x)\n}"
        #expect(diagnostics(source).map(\.description) == [expected])
    }

    @Test("a path that returns before a local is used needs no value in it")
    func returnsBeforeUse() {
        let source = """
            func main() {
                print(f(true))
                print(f(false))
            }
            func f(_ c: Bool) -> Int {
                let x: Int
                if c {
                    x = 5
                } else {
                    return 0
                }
                return x
            }
            """
        #expect(run(source) == RunResult(exitCode: 0, output: "5\n0\n", errors: ""))
    }

    @Test("a loop may run no pass, so a local it assigns isn't initialized on every path after it", arguments: [
        ("while i < 3 {\ni += 1\nx = copy i\n}", "8:7: error[E0305]: 'x' isn't initialized on every path"),
        ("while i < 3 {\ni += 1\nif i == 2 { continue }\nx = copy i\n}",
         "9:7: error[E0305]: 'x' isn't initialized on every path"),
        ("while true {\nif i == 0 { break }\nx = 1\nbreak\n}",
         "9:7: error[E0305]: 'x' isn't initialized on every path"),
    ])
    func loops(loop: String, expected: String) {
        #expect(errorLines(inMain: "var x: Int\nvar i = 0\n\(loop)\nprint(x)") == [expected])
    }

    @Test("a loop that a 'break' leaves only once the body has assigned a local leaves it initialized")
    func breakAfterAssignment() {
        let body = """
            let x: Int
            var i = 0
            while true {
                i += 1
                if i == 3 {
                    x = copy i
                    break
                }
            }
            print(x)
            """
        #expect(output(body) == "3\n")
    }

    @Test("a 'let' declared outside a loop and assigned in its body may be assigned again on the next pass",
          arguments: [
        ("while i < 3 {\ni += 1\nx = copy i\n}",
         "6:1: error[E0307]: 'x' is a 'let', and may have been assigned already"),
        ("while i < 3 {\ni += 1\nif i == 1 { continue }\nx = copy i\n}",
         "7:1: error[E0307]: 'x' is a 'let', and may have been assigned already"),
    ])
    func letInLoop(loop: String, expected: String) {
        #expect(errorLines(inMain: "let x: Int\nvar i = 0\n\(loop)") == [expected])
    }

    @Test("a local declared in a loop's body is a new local on each pass", arguments: [["--debug"], ["--release"]])
    func declaredInLoop(mode: [String]) {
        // A `let` declared in the body takes a new value on each pass.
        let source = """
            func main() {
                var i = 0
                while i < 3 {
                    i += 1
                    let x: Int
                    x = i * 10
                    print(x)
                }
            }
            """
        #expect(run(source, options: mode) == RunResult(exitCode: 0, output: "10\n20\n30\n", errors: ""))

        // A `var` declared in the body holds no value at the start of a pass, whatever the last pass assigned it.
        #expect(errorLines(inMain: "var i = 0\nwhile i < 3 {\ni += 1\nvar x: Int\nprint(x)\nx = copy i\n}") == [
            "6:7: error[E0304]: 'x' isn't initialized",
        ])
    }

    @Test("a 'let' is assigned at most once on each path, its declaration's value included",
          arguments: [
        ("let x: Int\nx = 1\nx = 2", ["4:1: error[E0306]: 'x' is a 'let', so it can't be assigned again"]),
        ("let x = 1\nx = 2\nx = 3", ["3:1: error[E0306]: 'x' is a 'let', so it can't be assigned again",
                                     "4:1: error[E0306]: 'x' is a 'let', so it can't be assigned again"]),
        ("let x = 1\nx += 1", ["3:1: error[E0306]: 'x' is a 'let', so it can't be assigned again"]),
        ("let x: Int\nif true { x = 1 }\nx = 2",
         ["4:1: error[E0307]: 'x' is a 'let', and may have been assigned already"]),
        ("let x: Int\nif true { x = 1 } else { x = 2 }\nprint(x)", []),
    ])
    func letAssignedOnce(body: String, expected: [String]) {
        #expect(errorLines(inMain: body) == expected)
    }

    @Test("a compound assignment's use comes before its store, so an error about each at one place comes in that order")
    func useBeforeStore() {
        #expect(errorLines(inMain: "let x: Int\nif true { x = 1 }\nx += 1") == [
            "4:1: error[E0305]: 'x' isn't initialized on every path",
            "4:1: error[E0307]: 'x' is a 'let', and may have been assigned already",
        ])
    }

    @Test("code that no path reaches may assign a 'let' twice and use a local that holds no value, since no run does")
    func unreachableCode() {
        #expect(errors("func main() {\nlet x: Int\nlet y: Int\nreturn\nx = 1\nx = 2\nprint(y)\n}") == [])
    }

    @Test("a 'let' that a move left without a value was still assigned, so it can't be assigned again")
    func letAssignedAfterMove() {
        #expect(errorLines(inMain: "let x: Int\nx = 1\nlet y = x\nx = 2") == [
            "5:1: error[E0306]: 'x' is a 'let', so it can't be assigned again",
        ])
    }

    @Test("a 'var' is assigned any number of times, and after a move it can't be used until the next")
    func varAssignedOften() {
        // A `var` takes a value again after a move.
        #expect(output("var x: Int\nx = 1\nlet y = x\nx = 2\nx = x + y\nprint(x)\nprint(y)") == "3\n1\n")

        // Between the move and the next assignment, it holds no value.
        #expect(errorLines(inMain: "var x: Int\nx = 1\nlet y = x\nprint(x)") == ["5:7: error[E0302]: 'x' was moved"])
    }

    @Test("a local moved on one path and never assigned on the other may have been moved")
    func movedOrUnassigned() {
        #expect(errorLines(inMain: "var x: Int\nif true {\nx = 1\nlet y = x\n}\nprint(x)") == [
            "7:7: error[E0303]: 'x' may have been moved",
        ])
    }
}
