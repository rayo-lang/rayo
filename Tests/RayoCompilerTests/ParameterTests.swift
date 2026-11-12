import Testing
import RayoDiagnostics

struct ParameterTests {
    @Test("each argument is written with its parameter's label, and the error covers the argument", arguments: [
        ("scaled(4, 5)", [ErrorCode.argumentLabel(expected: .label("by"), found: .none)], ["5"]),
        ("scaled(value: 4, by: 5)", [.argumentLabel(expected: .none, found: .label("value"))], ["value: 4"]),
        ("scaled(4, times: true)", [.argumentLabel(expected: .label("by"), found: .label("times")),
                                     .typeMismatch(expected: "Int", found: "Bool")], ["times: true", "true"]),
    ])
    func wrongLabels(call: String, expected: [ErrorCode], covered: [String]) {
        let source = "func main() { \(call) }\nfunc scaled(_ value: Int, by: Int) -> Int { copy value * copy by }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test("a parameter is borrowed: it can't change, and an expression reads it", arguments: [
        ("func f(x: Int) { x = 1 }", [ErrorCode.assignToParameter(name: "x")]),
        ("func f(x: Int) { x += 1 }", [.assignToParameter(name: "x")]),
        ("func f(x: Int) { x(1) }", [.notAFunction(name: "x")]),
        ("func f(x: Int) -> Int { copy x + x }", []),
    ])
    func borrowed(declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {}\n" + declaration) == expected)
    }

    @Test("a parameter's name is declared like a local's", arguments: [
        ("func f(a: Int, a: Bool) {}", [ErrorCode.alreadyDeclared(name: "a")]),
        ("func f(x: Int) { let x = 1 }", [.alreadyDeclared(name: "x")]),
        ("func f(_: Int) {}", [.underscoreDeclared]),
        ("func f(x: Int8) { print(x) }", [.notAType(name: "Int8")]),
    ])
    func names(declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {}\n" + declaration) == expected)
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
        ("func f(_ x: owned Int) { print(x) }", [ErrorCode.unsupportedConvention(convention: "owned")],
         ["_ x: owned Int"]),
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
        ("func main() {}\nfunc f(_ x: ()) {}", "()"),
        ("func main() { f(print(1)) }\nfunc f(_ x: Void) {}", "Void"),
        ("func main() {\n    f(1)\n    f(print(1))\n}\nfunc f(_ x: ()) {}\nfunc f(_ x: Int) {}", "()"),
    ])
    func voidParameter(source: String, covered: String) {
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.voidParameter])
        #expect(coveredText(reported, in: source) == [covered])
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
