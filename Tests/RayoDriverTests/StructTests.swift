import Testing
import RayoDiagnostics
import RayoDriver

/// Two structs, one holding the other.
private let shotAndHit = "\nstruct Shot(var hit: Hit)\nstruct Hit(var damage: Int)"

struct StructTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a struct's name is a type, which locals, parameters and results may have, in debug and in release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var shot: Shot
                print(1)
            }
            func relay(_ s: Shot) -> Shot { kept(s) }
            func kept(_ s: Shot) -> Shot {
                var k: Shot
                k = copy s
                let t = k
                return t
            }
            struct Shot(var hit: Hit, let team: Bool)
            struct Hit(var damage: Int)
            """
        #expect(run(source, options: mode) == Driver.Result(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test(arguments: [
        ("let i: Int = copy s", ErrorCode.typeMismatch(expected: "Int", found: "S")),
        ("let e: E = copy s", .typeMismatch(expected: "E", found: "S")),
        ("print(s)", .typeMismatch(expected: "Int", found: "S")),
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

    @Test func `a local may share a struct's name, which a type names the struct by, and any other use the local`() {
        let body = "let S = 2\nvar s: S\nprint(S)"
        #expect(run("func main() {\n\(body)\n}\nstruct S(var a: Int)") ==
            Driver.Result(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test(arguments: [
        ("let x: Int = 1", "struct Int(var big: Bool)", [ErrorCode.typeMismatch(expected: "Int", found: "Int")]),
        ("print(1)", "struct print", [.notDeclared(name: "print")]),
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
    ])
    func `a field has a name of its own and a type that isn't Void, and the error covers what is wrong`(
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
        #expect(errors("func main() {}\n" + declarations) == names.map { .containsItself(name: $0) })
    }
}
