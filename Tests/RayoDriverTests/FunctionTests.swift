import Testing
import RayoDiagnostics
import RayoDriver

struct FunctionTests {
    @Test("a call runs a function declared after it, and gives what the function returns")
    func callBeforeDeclaration() {
        #expect(run("func main() { print(answer()) }\nfunc answer() -> Int { 42 }") ==
            Driver.Result(exitCode: 0, output: "42\n", errors: ""))
    }

    @Test("'return' leaves the function, with its value when it has one, and code after it doesn't run")
    func returns() {
        let source = """
            func main() {
                report()
                print(double())
            }
            func report() {
                print(1)
                if true { return }
                print(2)
            }
            func double() -> Int {
                var x = 20
                while true {
                    x += 1
                    return x * 2
                }
            }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n42\n", errors: ""))
    }

    @Test("what a function returns has its result type, and a local's value is returned with 'copy'", arguments: [
        ("func f() -> Int { return true }", [ErrorCode.typeMismatch(expected: "Int", found: "Bool")]),
        ("func f() -> Bool { 1 }", [.typeMismatch(expected: "Bool", found: "Int")]),
        ("func f() -> Int { print(1) }", [.typeMismatch(expected: "Int", found: "Void")]),
        ("func f() -> Int { return }", [.missingReturnValue(type: "Int")]),
        ("func f() { return 1 }", [.typeMismatch(expected: "Void", found: "Int")]),
        ("func f() -> Void { return 1 }", [.typeMismatch(expected: "Void", found: "Int")]),
        ("func f() -> Int {\n    let x = 1\n    return x\n}", [.takenWithoutCopy(name: "x")]),
        ("func f() -> Int8 { return true }", [.notAType(name: "Int8")]),
        ("func main() -> Int { return 1 }", [.mainReturnsNonVoid]),
    ])
    func returnedValues(declaration: String, expected: [ErrorCode]) {
        let source = declaration.hasPrefix("func main") ? declaration : "func main() {}\n" + declaration
        #expect(errors(source) == expected)
    }

    @Test("a function with a result ends every path in 'return', or in a loop that never ends", arguments: [
        "if 1 < 2 { return 1 } else if true { return 2 } else { return 3 }",
        "return 1\nprint(2)",
        "if true { } else { }\nvar i = 0\nwhile (true) {\ni += 1\nif i == 1 { return copy i }\n}",
        "while true {\nwhile true { break }\nif 2 > 1 { return 1 }\n}",
    ])
    func everyPathReturns(body: String) {
        #expect(run("func main() { print(f()) }\nfunc f() -> Int {\n\(body)\n}") ==
            Driver.Result(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("a function with a result can't reach its end, and the error covers the '}' it reaches", arguments: [
        "", "print(1)\nprint(2)", "if true { return 1 }", "if true { return 1 } else { }",
        "while 1 < 2 { return 1 }", "while true { break }", "while true {\nif false { break }\n}",
    ])
    func endReached(body: String) {
        let source = "func main() {}\nfunc f() -> Int {\n\(body)\n}"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.missingReturn(signature: "f()")])
        #expect(coveredText(reported, in: source) == ["}"])
        #expect(reported.first?.range.start.offset == source.utf8.count - 1)
    }

    @Test("a function without '->' whose body is one expression returns that expression's type")
    func inferredResult() {
        let source = """
            func main() {
                if positive() { print(seven()) }
                say()
            }
            func positive() { seven() > 0 }
            func seven() { 3 + 4 }
            func say() { print(1) }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "7\n1\n", errors: ""))
        #expect(errors("func main() { let x = say() }\nfunc say() { print(1) }") == [.voidLocal])
        #expect(errors("func main() { let x = f() }\nfunc f() {\n    print(1)\n    3\n}") ==
            [.voidLocal, .unusedValue(type: "Int")])
    }

    @Test("a result type that depends on itself is an error at the call that closes the cycle", arguments: [
        ("func f() { f() }", "f()", "f()"),
        ("func f() { g() + 1 }\nfunc g() { f() }", "f()", "f()"),
        ("func f() { g() }\nfunc g() { 1 + h() }\nfunc h() { f() }", "f()", "f()"),
    ])
    func resultCycle(declarations: String, call: String, signature: String) {
        let source = "func main() {}\n" + declarations
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.resultDependsOnItself(signature: signature)])
        #expect(coveredText(reported, in: source) == [call])
    }

    @Test("a written result type ends what a result type depends on")
    func writtenResultEndsCycle() {
        #expect(errors("func main() { print(f()) }\nfunc f() -> Int { g() }\nfunc g() { 1 + f() }") == [])
    }

    @Test("functions may call themselves and each other, in any order")
    func recursion() {
        let source = """
            func main() { print(even()) }
            func even() -> Int {
                if true { return 1 }
                return odd()
            }
            func odd() -> Int { even() }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("a function's name is declared once, and the second declaration is still checked")
    func declaredTwice() {
        let source = "func main() { print(f()) }\nfunc f() -> Int { 1 }\nfunc f() -> Bool { 2 }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [
            .functionDeclaredTwice(signature: "f()"), .typeMismatch(expected: "Bool", found: "Int"),
        ])
        #expect(coveredText(reported, in: source) == ["f", "2"])
    }

    @Test("a function the file declares shadows the prelude's function of that name")
    func shadowsPrelude() {
        #expect(errors("func main() { print(1) }\nfunc print() {}") ==
            [.argumentCount(name: "print", takes: 0, passes: 1)])
    }

    @Test("a function is called, not used as a value, assigned or declared again", arguments: [
        ("let g = f", ErrorCode.functionAsValue(name: "f")),
        ("print(f)", .functionAsValue(name: "f")),
        ("f = 2", .assignToFunction(name: "f")),
        ("let f = 1", .alreadyDeclared(name: "f")),
        ("f(1)", .argumentCount(name: "f", takes: 0, passes: 1)),
    ])
    func notAValue(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}\nfunc f() -> Int { 1 }") == [expected])
    }

    @Test("a panic in a function names its place in that function")
    func panicInCallee() {
        let source = "func main() {\n    print(1)\n    print(f())\n}\nfunc f() -> Int {\n    return 1 / zero()\n}\nfunc zero() { 0 }"
        #expect(run(source) == Driver.Result(exitCode: Driver.panicExitCode, output: "1\n",
                                             errors: "main.rayo:6:12: panic: division by zero\n"))
    }

    @Test("functions may take the names of the runtime's functions and of the C functions it calls")
    func runtimeNames() {
        let source = """
            func main() {
                print(printf() + write() + exit() + fflush())
                print(1 / 0)
            }
            func printf() { 1 }
            func write() { 2 }
            func exit() { 3 }
            func fflush() { 4 }
            func print_int() {}
            func panic() {}
            """
        #expect(run(source) == Driver.Result(exitCode: Driver.panicExitCode, output: "10\n",
                                             errors: "main.rayo:3:11: panic: division by zero\n"))
    }

    @Test("a Void function returns a Void value, and 'return' alone", arguments: [
        "func f() { return print(1) }", "func f() -> () { return }", "func main() { return }",
    ])
    func voidReturns(declaration: String) {
        let source = declaration.hasPrefix("func main") ? declaration : "func main() { f() }\n" + declaration
        #expect(run(source) == Driver.Result(exitCode: 0, output: declaration.contains("print") ? "1\n" : "",
                                             errors: ""))
    }
}
