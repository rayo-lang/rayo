import Testing
import RayoCheckedProgram
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

    @Test("a '&T' parameter is borrowed: it can't change, and an expression reads it", arguments: [
        ("func f(x: &Int) { x = 1 }", [ErrorCode.assignToParameter(name: "x")]),
        ("func f(x: &Int) { x += 1 }", [.assignToParameter(name: "x")]),
        ("func f(x: &Int) { x(1) }", [.notAFunction(name: "x")]),
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

    @Test func `functions whose parameters differ only in how they take their arguments are declared once each`() {
        #expect(errors("func main() {}\nfunc f(_ x: &Int) {}\nfunc f(_ x: Int) {}") == [])
        #expect(errors("func main() {}\nfunc f(_ x: &Int) {}\nfunc f(_ y: &Int) {}") == [
            .functionDeclaredTwice(signature: "f(_: &Int)"),
        ])
    }

    // An argument written with a `&` reaches the function that borrows it, and one written without reaches the one
    // that owns it. A bare argument that only a function that borrows it takes is lent, and one that every function
    // its type fits borrows counts as written with a `&`, so it tells none of them apart. Where several still fit,
    // each lending a different argument or the same one, the call is ambiguous. A place that holds a reference, such
    // as a `ref let`, is of a reference type already, and an owning parameter takes its value. Where none takes a `&`
    // written for an argument, the one its type fits reports how to write it, and where they take the arguments in
    // different ways, the call fits none of them, which spells each `&` it writes.
    @Test(arguments: [
        ("f(&a)", [ErrorCode]()), ("f(a)", []), ("f(1)", []), ("g(a)", []), ("k(a, a)", []), ("k(a, &a)", []),
        ("ref let r = &a\n    h(r)", []), ("f(if a > 0 { a } else { &a })", []),
        ("h(&a)", [.referenceToOwnedParameter(name: "h", type: "Int")]),
        ("u(1)", [.ambiguousCall(name: "u")]), ("v(1, 2)", [.ambiguousCall(name: "v")]),
        ("w(&a, &a)", [.noMatchingFunction(name: "w", arguments: "&Int, &Int")]),
        ("g(&b)", [.noMatchingFunction(name: "g", arguments: "&UInt")]),
    ] as [(String, [ErrorCode])])
    func `an overload is picked by how each argument is written, where its type fits several`(
        call: String, expected: [ErrorCode],
    ) {
        let declarations = """
            func f(_ x: &Int) {}
            func f(_ x: Int) {}
            func g(_ x: &Int) {}
            func g(_ x: &Bool) {}
            func h(_ x: Int) {}
            func h(_ x: Bool) {}
            func u(_ x: &Int) {}
            func u(_ x: &UInt) {}
            func v(_ x: &Int, _ y: Int) {}
            func v(_ x: UInt, _ y: &UInt) {}
            func k(_ x: &Int, _ y: Int) {}
            func k(_ x: &Int, _ y: &Int) {}
            func w(_ x: Int, _ y: &Int) {}
            func w(_ x: &Int, _ y: Int) {}
            """
        let locals = "let a = 1\n    let b: UInt = 1"
        #expect(errors("func main() {\n    \(locals)\n    \(call)\n}\n\(declarations)") == expected)
    }

    // A `mutable &T` parameter holds a reference too, but a bare one given to a `&T` parameter reborrows through it,
    // as `&r` does, so only a shared reference fits a `&T` with no conversion.
    @Test(arguments: [
        (LocalKind.refLet, true), (.parameter(.borrowed), true), (.parameter(.mutable), false),
        (.parameter(.owned), false), (.let, false), (.var, false),
    ])
    func `a 'ref let' and a parameter that borrows its argument hold a shared reference, and no other local does`(
        kind: LocalKind, holdsSharedReference: Bool,
    ) {
        #expect(kind.holdsSharedReference == holdsSharedReference)
    }

    @Test("a function the file declares hides every prelude function of its name")
    func shadowsPrint() {
        #expect(errors("func main() { print(1) }\nfunc print(_ b: Bool) {}") ==
            [.typeMismatch(expected: "Bool", found: "Int")])
    }

    @Test("'mutable &' parameters and default values aren't supported", arguments: [
        ("func f(x: mutable &Int) {}", [ErrorCode.unsupportedConvention(convention: "mutable &")],
         ["x: mutable &Int"]),
        ("func f(x: Int = 1 + 2) {}", [.defaultArgument], ["1 + 2"]),
    ])
    func unsupported(declaration: String, expected: [ErrorCode], covered: [String]) {
        let source = "func main() {}\n" + declaration
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test("a parameter can't have type Void, and the error covers its type, whether or not the function is called",
          arguments: [
        ("func main() {}\nfunc f(_ x: ()) {}", "()"),
        ("func main() { f(print(1)) }\nfunc f(_ x: Void) {}", "Void"),
        ("func main() {\n    f(1)\n    f(print(1))\n}\nfunc f(_ x: ()) {}\nfunc f(_ x: Int) {}", "()"),
    ])
    func voidParameter(source: String, covered: String) {
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.voidParameter(name: "x", type: "Void")])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test func `a parameter of type Void is reported by its name`() {
        #expect(diagnostics("func main() {}\nfunc f(_ x: Void) {}").map(\.description) == [
            "2:13: error[E0234]: the parameter 'x' can't have type Void",
        ])
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
