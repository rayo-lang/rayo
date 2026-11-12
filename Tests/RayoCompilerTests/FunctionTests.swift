import Testing
import RayoDiagnostics

struct FunctionTests {
    @Test("what a function returns has its result type", arguments: [
        ("func f() -> Int { return true }", [ErrorCode.typeMismatch(expected: "Int", found: "Bool")]),
        ("func f() -> Bool { 1 }", [.typeMismatch(expected: "Bool", found: "Int")]),
        ("func f() -> Int { print(1) }", [.typeMismatch(expected: "Int", found: "Void")]),
        ("func f() -> Int { return }", [.missingReturnValue(type: "Int")]),
        ("func f() { return 1 }", [.typeMismatch(expected: "Void", found: "Int")]),
        ("func f() -> Void { return 1 }", [.typeMismatch(expected: "Void", found: "Int")]),
        ("func f() -> Int8 { return true }", [.notAType(name: "Int8")]),
        ("func main() -> Int { return 1 }", [.mainReturnsNonVoid]),
    ])
    func returnedValues(declaration: String, expected: [ErrorCode]) {
        let source = declaration.hasPrefix("func main") ? declaration : "func main() {}\n" + declaration
        #expect(errors(source) == expected)
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

    @Test("a function without '->' returns Void when its body is a Void expression, or more than one statement")
    func inferredResult() {
        #expect(errors("func main() { let x = say() }\nfunc say() { print(1) }") == [.voidLocal])
        #expect(errors("func main() { let x = f() }\nfunc f() {\n    print(1)\n    3\n}") ==
            [.voidLocal, .unusedValue(value: TypedValue(type: "Int"))])
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

    @Test(arguments: ["Int", "Bool", "Void"], [
        "func main() {\n    let x: {T} = true\n    print(x)\n}",
        "func main() {}\nfunc f(_ b: {T}) {}",
        "func main() {}\nfunc f() -> {T} { true }",
        "func main() {}\nstruct S(var b: {T})",
    ])
    func `a function shadows the prelude's type of its name wherever a type names it, and the error covers the name`(
        type: String, declarations: String,
    ) {
        let source = declarations.replacing("{T}", with: type) + "\nfunc \(type)() {}"

        // The one error is that the name isn't a type, and it covers the name.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.notAType(name: type)])
        #expect(coveredText(reported, in: source) == [type])
    }

    @Test func `an error names a prelude type that a function shadows as the prelude's`() {
        #expect(errors("func main() {\n    let b: Bool = 1\n}\nfunc Int() {}") ==
            [.typeMismatch(expected: "Bool", found: .shadowedPrelude("Int"))])
    }

    @Test("a function is called, not used as a value or assigned", arguments: [
        ("let g = f", ErrorCode.functionAsValue(name: "f")),
        ("print(f)", .functionAsValue(name: "f")),
        ("f = 2", .assignToFunction(name: "f")),
        ("f(1)", .argumentCount(name: "f", takes: 0, passes: 1)),
    ])
    func notAValue(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}\nfunc f() -> Int { 1 }") == [expected])
    }
}
