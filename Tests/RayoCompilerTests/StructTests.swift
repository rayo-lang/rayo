import Testing
import RayoDiagnostics

/// Two structs, one holding the other.
private let shotAndHit = "\nstruct Shot(var hit: Hit)\nstruct Hit(var damage: Int)"

struct StructTests {
    @Test(arguments: [
        ("let i: Int = copy s", ErrorCode.typeMismatch(expected: "Int", found: "S")),
        ("let e: E = copy s", .typeMismatch(expected: "E", found: "S")),
        ("print(s)", .noMatchingFunction(name: "print", arguments: "S")),
        ("let t = s + s", .operandTypes(op: "+", needs: "Int", left: "S", right: "S")),
        ("let b = s == s", .incomparable(op: "==", type: "S")),
    ])
    func `a value of a struct's type has no other type, and '==' can't compare it`(body: String, expected: ErrorCode) {
        #expect(errors("func main() {}\nfunc f(_ s: S) {\n\(body)\n}\nstruct S(var a: Int)\nstruct E") == [expected])
    }

    @Test(arguments: [
        ("func f(_ s: Shot) -> Shot { s }", "s"),
        ("func f(_ s: Shot) {\n    _ = s\n}", "s"),
    ])
    func `a borrowed parameter of a struct type can't be moved, and the error covers the parameter`(
        declaration: String, name: String,
    ) {
        let source = "func main() {}\n\(declaration)" + shotAndHit

        // The one error is the move, and it covers the parameter's name.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.moveFromParameter(name: name)])
        #expect(coveredText(reported, in: source) == [name])
    }

    @Test(arguments: [
        ("S()", ErrorCode.structInitializer),
        ("let s = S", .typeAsValue(name: "S")),
        ("S = 1", .assignToType(name: "S")),
    ])
    func `a struct's name used as a call, a value or an assignment's target is reported as a struct's`(
        body: String, expected: ErrorCode,
    ) {
        let source = "func main() {\n\(body)\n}\nstruct S(var a: Int)"

        // The one error covers the struct's name.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == ["S"])
    }

    @Test(arguments: [
        ("let x: Int = 1", "struct Int(var big: Bool)", [ErrorCode.typeMismatch(expected: "Int", found: "Int")]),
        ("print(1)", "struct print", [.structInitializer]),
    ])
    func `a struct's name shadows the prelude's type or function of that name`(
        body: String, declaration: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {\n\(body)\n}\n\(declaration)") == expected)
    }
}

struct StructDeclarationTests {
    @Test(arguments: [
        ("struct S(var a: Q)", ErrorCode.notAType(name: "Q"), "Q"),
        ("struct S(var a: Void)", .voidField, "Void"),
        ("struct S(var a: ())", .voidField, "()"),
        ("struct S(var a)", .missingFieldType(name: "a"), "a"),
        ("struct S(var a: Int, let a: Bool)", .alreadyDeclared(name: "a"), "a"),
        ("struct S(var _: Int)", .underscoreDeclared, "_"),
        ("struct S(var a: Int = 1)", .fieldDefault, "1"),
        ("struct S(var a = 1 + 2)", .fieldDefault, "1 + 2"),
    ])
    func `a field has a name of its own, a type that isn't Void and no default, and the error covers what is wrong`(
        declaration: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {}\n" + declaration

        // The one error is the field's, and it covers what is wrong with it.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        "struct S\nstruct S(var a: Int)", "struct S\nfunc S() {}", "func S() {}\nstruct S",
    ])
    func `a name at a file's top level names one struct, or functions, and the error covers the later name`(
        declarations: String,
    ) {
        let source = "func main() {}\n" + declarations

        // The one error is at the later of the two declarations, on the file's third line.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.alreadyDeclared(name: "S")])
        #expect(reported.map(\.range.start.line) == [3])
    }

    @Test(arguments: [
        ("func main() {}\nfunc S() {}\nstruct S\nfunc g(_ s: S) {}", "S"),
        ("func main() {}\nfunc S() {}\nstruct S\nfunc S(_ x: Int) {}", "S"),
        ("func main() {\n    S()\n}\nstruct S\nfunc S() {}", "S"),
        ("struct main\nfunc main() {}", "main"),
    ])
    func `a struct or function whose name is taken is still declared, so its uses raise no error of their own`(
        source: String, name: String,
    ) {
        #expect(errors(source) == [.alreadyDeclared(name: name)])
    }

    @Test(arguments: [
        ("struct A\nfunc A() {}", "let q = A", ErrorCode.typeAsValue(name: "A")),
        ("struct A\nfunc A() {}", "A = 3", .assignToType(name: "A")),
        ("func A() {}\nstruct A", "let q = A", .functionAsValue(name: "A")),
        ("func A() {}\nstruct A", "A = 3", .assignToFunction(name: "A")),
    ])
    func `a body's use of a taken name, other than a call, finds the kind that declares the name first`(
        declarations: String, body: String, expected: ErrorCode,
    ) {
        #expect(errors("func main() {\n\(body)\n}\n" + declarations) == [expected, .alreadyDeclared(name: "A")])
    }

    @Test func `each function after a struct of its name is an error, though it overloads another`() {
        let reported = diagnostics("func main() {}\nstruct f\nfunc f() {}\nfunc f(_ x: Int) {}")
        #expect(reported.map(\.code) == [.alreadyDeclared(name: "f"), .alreadyDeclared(name: "f")])
        #expect(reported.map(\.range.start.line) == [3, 4])
    }

    @Test func `'_' can't name a struct`() {
        #expect(errors("func main() {}\nstruct _") == [.underscoreDeclared])
    }

    @Test(arguments: [
        ("struct C(var next: C)", ["C"]),
        ("struct A(var b: B)\nstruct B(var a: A)", ["A", "B"]),
        ("struct A(var b: B)\nstruct B(var c: C)\nstruct C(var b: B)", ["B", "C"]),
    ])
    func `a struct can't contain itself, through its fields at any depth, and each struct in the cycle is an error`(
        declarations: String, names: [String],
    ) {
        let source = "func main() {}\n" + declarations

        // Each error covers the name of a struct on the cycle.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == names.map { .containsItself(name: $0) })
        #expect(coveredText(reported, in: source) == names)
    }
}
