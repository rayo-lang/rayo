import Testing
import RayoDiagnostics
import RayoDriver

struct ParameterTests {
    @Test("a call passes its arguments to the parameters in order, labeled as the parameters are declared")
    func labels() {
        let source = """
            func main() {
                print(difference(from: 10, take: 3))
                print(scaled(4, by: 5))
            }
            func difference(from a: Int, take b: Int) -> Int { a - b }
            func scaled(_ value: Int, by: Int) -> Int { value * by }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "7\n20\n", errors: ""))
    }

    @Test("functions recurse, directly and through each other, in debug and in release", arguments: [["--debug"], ["--release"]])
    func recursion(mode: [String]) {
        let source = """
            func main() {
                print(fibonacci(20))
                if isEven(7) { print(1) } else { print(0) }
                print(sum(to: 100000))
            }
            func fibonacci(_ n: Int) -> Int {
                if n < 2 { return copy n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }
            func isEven(_ n: Int) -> Bool {
                if n == 0 { return true }
                return isOdd(n - 1)
            }
            func isOdd(_ n: Int) -> Bool { n != 0 && isEven(n - 1) }
            func sum(to n: Int) -> Int {
                if n == 0 { return 0 }
                return n + sum(to: n - 1)
            }
            """
        #expect(run(source, options: mode) == Driver.Result(exitCode: 0, output: "6765\n0\n5000050000\n", errors: ""))
    }

    @Test("arguments are evaluated left to right, before the call")
    func evaluationOrder() {
        let source = """
            func main() { print(pair(shown(1), shown(2))) }
            func shown(_ x: Int) -> Int {
                print(copy x)
                return copy x
            }
            func pair(_ a: Int, _ b: Int) -> Int { a * 10 + b }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n2\n12\n", errors: ""))
    }

    @Test("a panic in a function names its place there, whatever its arguments")
    func panicInCallee() {
        let source = "func main() {\n    print(ratio(6, 3))\n    print(ratio(1, 0))\n}\nfunc ratio(_ a: Int, _ b: Int) -> Int {\n    return a / b\n}"
        #expect(run(source) == Driver.Result(exitCode: Driver.panicExitCode, output: "2\n",
                                             errors: "main.rayo:6:12: panic: division by zero\n"))
    }

    @Test("each argument is written with its parameter's label, and the error covers the argument", arguments: [
        ("scaled(4, 5)", [ErrorCode.argumentLabel(expected: .label("by"), found: .none)], ["5"]),
        ("scaled(value: 4, by: 5)", [.argumentLabel(expected: .none, found: .label("value"))], ["value: 4"]),
        ("print(value: 1)", [.argumentLabel(expected: .none, found: .label("value"))], ["value: 1"]),
        ("scaled(4, times: true)", [.argumentLabel(expected: .label("by"), found: .label("times")),
                                     .typeMismatch(expected: "Int", found: "Bool")], ["times: true", "true"]),
    ])
    func wrongLabels(call: String, expected: [ErrorCode], covered: [String]) {
        let source = "func main() { \(call) }\nfunc scaled(_ value: Int, by: Int) -> Int { copy value * copy by }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test("a keyword can be an argument label")
    func keywordLabels() {
        #expect(run("func main() { print(pick(if: true, else: 2)) }\nfunc pick(if c: Bool, else e: Int) -> Int { copy e }")
            == Driver.Result(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test("a parameter is borrowed: it can't change, and its value is taken with 'copy'", arguments: [
        ("func f(x: Int) { x = 1 }", [ErrorCode.assignToParameter(name: "x")]),
        ("func f(x: Int) { x += 1 }", [.assignToParameter(name: "x")]),
        ("func f(x: Int) -> Int { x }", [.takenWithoutCopy(name: "x")]),
        ("func f(x: Int) { let y = x }", [.takenWithoutCopy(name: "x")]),
        ("func f(x: Int) { x(1) }", [.notAFunction(name: "x")]),
        ("func f(x: Int) -> Int { copy x + x }", []),
    ])
    func borrowed(declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {}\n" + declaration) == expected)
    }

    @Test("a parameter's name is declared like a local's", arguments: [
        ("func f(a: Int, a: Bool) {}", [ErrorCode.alreadyDeclared(name: "a")]),
        ("func f(f: Int) {}", [.alreadyDeclared(name: "f")]),
        ("func f(x: Int) { let x = 1 }", [.alreadyDeclared(name: "x")]),
        ("func f(_: Int) {}", [.underscoreDeclared]),
        ("func f(x: Int8) { print(x) }", [.notAType(name: "Int8")]),
    ])
    func names(declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {}\n" + declaration) == expected)
    }

    @Test("functions may share a name when their labels or parameter types differ, and a call picks the one it fits")
    func overloads() {
        let source = """
            func main() {
                print(kind(5))
                print(kind(true))
                print(kind(of: 5))
                print(kind())
            }
            func kind(_ x: Int) { 1 }
            func kind(_ b: Bool) -> Int { 2 }
            func kind(of x: Int) -> Int { 3 }
            func kind() -> Int { 4 }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n2\n3\n4\n", errors: ""))
    }

    @Test("a call that fits none of a name's functions is an error, unless an argument already is", arguments: [
        ("kind(x: 1)", [ErrorCode.noMatchingFunction(name: "kind", arguments: "x: Int")]),
        ("kind(1, true)", [.noMatchingFunction(name: "kind", arguments: "Int, Bool")]),
        ("kind(nope)", [.notDeclared(name: "nope")]),
    ])
    func noOverloadFits(call: String, expected: [ErrorCode]) {
        let source = "func main() { \(call) }\nfunc kind(_ x: Int) {}\nfunc kind(_ b: Bool) {}"
        #expect(errors(source) == expected)
    }

    @Test("functions that differ only in their parameters' names or their result types are declared twice")
    func declaredTwice() {
        let source = "func main() {}\nfunc f(_ x: Int, y: Bool) {}\nfunc f(_ a: Int, y b: Bool) -> Int { 1 }"
        #expect(errors(source) == [.functionDeclaredTwice(signature: "f(_: Int, y: Bool)")])
    }

    @Test("a function the file declares hides every prelude function of its name")
    func shadowsPrint() {
        #expect(errors("func main() { print(1) }\nfunc print(_ b: Bool) {}") ==
            [.typeMismatch(expected: "Bool", found: "Int")])
    }

    @Test("'owned' and 'mutable' parameters and default values aren't supported", arguments: [
        ("func f(_ x: owned Int) { print(x) }", [ErrorCode.unsupportedConvention(convention: "owned")], ["_ x: owned Int"]),
        ("func f(x: mutable Int) {}", [.unsupportedConvention(convention: "mutable")], ["x: mutable Int"]),
        ("func f(x: Int = 1 + 2) {}", [.defaultArgument], ["1 + 2"]),
        ("func f(owned: Int) { print(owned) }", [], []),
        ("func f(x: owned) {}", [.notAType(name: "owned")], ["owned"]),
    ])
    func unsupported(declaration: String, expected: [ErrorCode], covered: [String]) {
        let source = "func main() {}\n" + declaration
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test("an argument isn't lent with '&'")
    func noAmpersand() {
        #expect(errors("func main() {\n    var x = 1\n    f(&x)\n}\nfunc f(x: Int) {}") ==
            [.unexpectedCharacter(character: "&")])
    }

    @Test("a parameter can't have type Void, and the error covers its type, whether or not the function is called",
          arguments: [
        "func main() {}\nfunc f(_ x: ()) {}",
        "func main() { f(print(1)) }\nfunc f(_ x: Void) {}",
        "func main() {\n    f(1)\n    f(print(1))\n}\nfunc f(_ x: ()) {}\nfunc f(_ x: Int) {}",
    ])
    func voidParameter(source: String) {
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.voidParameter])
        #expect(["()", "Void"].contains(coveredText(reported, in: source).first ?? ""))
        #expect(run(source).diagnostics.map(\.code) == [.voidParameter])
    }

    @Test("overloads whose parameter types aren't types aren't declared twice")
    func unknownTypesDiffer() {
        #expect(errors("func main() {}\nfunc f(_ x: Foo) {}\nfunc f(_ x: Bar) {}") ==
            [.notAType(name: "Foo"), .notAType(name: "Bar")])
    }

    @Test("a parameter named '_' with no label written takes an argument with no label")
    func underscoreName() {
        #expect(errors("func main() { print(f(1)) }\nfunc f(_: Int) -> Int { 1 }") == [.underscoreDeclared])
    }

    @Test("an error about a function's end names its signature")
    func missingReturnSignature() {
        #expect(errors("func main() {}\nfunc f(_ x: Int, y: Bool) -> Int {}") ==
            [.missingReturn(signature: "f(_: Int, y: Bool)")])
    }

    @Test("'main' takes no parameters, and the error covers the first")
    func mainParameters() {
        let source = "func main(_ x: Int, y: Bool) {}"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.mainTakesParameters])
        #expect(coveredText(reported, in: source) == ["_ x: Int"])
    }
}
