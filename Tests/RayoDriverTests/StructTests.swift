import Testing
import RayoDiagnostics
import RayoDriver

/// Two structs, one holding the other.
private let shotAndHit = "\nstruct Shot(var hit: Hit)\nstruct Hit(var damage: Int)"

struct StructTests {
    @Test("a struct's name is a type, which locals, parameters and results may have, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func types(mode: [String]) {
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

    @Test("initializers make struct values, which locals hold and calls pass and return, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func values(mode: [String]) {
        let source = """
            func main() {
                var p: Pair
                p = pair(3)
                let q = p
                print(weight(q))
                let outer = Outer(flag: true, hit: Hit(crit: false, damage: 4, team: true), count: 9)
                var moved = outer
                moved = Outer(flag: false, hit: Hit(crit: true, damage: 1, team: false), count: 2)
                let e = Empty()
                let f = e
                print(weight(pair(5)))
            }
            func pair(_ a: Int) -> Pair { Pair(a: copy a, b: 2) }
            func weight(_ p: Pair) -> Int { 2 }
            struct Outer(let flag: Bool, var hit: Hit, var count: Int)
            struct Pair(var a: Int, var b: Int)
            struct Hit(var crit: Bool, var damage: Int, let team: Bool)
            struct Empty
            """
        #expect(run(source, options: mode) == Driver.Result(exitCode: 0, output: "2\n2\n", errors: ""))
    }

    @Test("a value of a struct's type has no other type, and '==' can't compare it", arguments: [
        ("let i: Int = copy s", ErrorCode.typeMismatch(expected: "Int", found: "S")),
        ("let e: E = copy s", .typeMismatch(expected: "E", found: "S")),
        ("print(s)", .typeMismatch(expected: "Int", found: "S")),
        ("let t = s + s", .operandTypes(op: "+", needs: "Int", left: "S", right: "S")),
        ("let b = s == s", .incomparable(op: "==", type: "S")),
    ])
    func typeErrors(body: String, expected: ErrorCode) {
        #expect(errors("func main() {}\nfunc f(_ s: S) {\n\(body)\n}\nstruct S(var a: Int)\nstruct E") == [expected])
    }

    @Test("the primary initializer takes its arguments owned, so a local passed to it is moved", arguments: [
        ("let h = Hit(damage: 1)\nlet s = Shot(hit: h)\nlet t = h", "4:9: error[E0302]: 'h' was moved"),
        ("let d = 1\nlet h = Hit(damage: d)\nprint(d)", "4:7: error[E0302]: 'd' was moved"),
    ])
    func initializerMoves(body: String, expected: String) {
        #expect(diagnostics("func main() {\n\(body)\n}" + shotAndHit).map(\.description) == [expected])
    }

    @Test("an initializer passed a 'copy' of a local takes a copy of its value, and the local keeps its own")
    func initializerCopies() {
        let body = "let h = Hit(damage: 1)\nlet s = Shot(hit: copy h)\nlet t = h"
        #expect(errors("func main() {\n\(body)\n}" + shotAndHit) == [])
    }

    @Test("taking a struct value moves it, and the error is at the later use", arguments: [
        ("let t = s", "4:9"), ("_ = s", "4:9"), ("var t: Shot\nt = s", "5:9"),
    ])
    func moves(taking: String, laterUse: String) {
        let body = "let s = Shot(hit: Hit(damage: 1))\n\(taking)\nlet u = s"
        #expect(diagnostics("func main() {\n\(body)\n}" + shotAndHit).map(\.description) == [
            "\(laterUse): error[E0302]: 's' was moved",
        ])
    }

    @Test("a borrowed parameter of a struct type can't be moved, and the error covers the parameter", arguments: [
        ("func f(_ s: Shot) -> Shot { s }", "s"),
        ("func f(_ h: Hit) -> Shot { Shot(hit: h) }", "h"),
        ("func f(_ s: Shot) {\n    _ = s\n}", "s"),
    ])
    func borrowedParameter(declaration: String, name: String) {
        let source = "func main() {}\n\(declaration)" + shotAndHit
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.moveFromParameter(name: name)])
        #expect(coveredText(reported, in: source) == [name])
    }

    @Test("a local may share a struct's name, which a call and a type name the struct by, and any other use the local")
    func localSharesName() {
        let body = "let S = 2\nlet s: S = S(a: copy S)\nprint(S)"
        #expect(run("func main() {\n\(body)\n}\nstruct S(var a: Int)") ==
            Driver.Result(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test("a struct's name shadows the prelude's type or function of that name", arguments: [
        ("let x: Int = Int(big: true)", "struct Int(var big: Bool)", []),
        ("print(1)", "struct print", [ErrorCode.argumentCount(name: "print", takes: 0, passes: 1)]),
    ])
    func shadowsPrelude(body: String, declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}\n\(declaration)") == expected)
    }
}

struct StructDeclarationTests {
    @Test("a field has a name of its own and a type that isn't Void, and the error covers what is wrong", arguments: [
        ("struct S(var a: Q)", ErrorCode.notAType(name: "Q"), "Q"),
        ("struct S(var a: Void)", .voidField, "Void"),
        ("struct S(var a: ())", .voidField, "()"),
        ("struct S(var a)", .missingFieldType(name: "a"), "a"),
        ("struct S(var a: Int, let a: Bool)", .alreadyDeclared(name: "a"), "a"),
        ("struct S(var _: Int)", .underscoreDeclared, "_"),
    ])
    func fields(declaration: String, expected: ErrorCode, covered: String) {
        let source = "func main() {}\n" + declaration
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test("a name at a file's top level names one struct, or functions, and the error covers the later name",
          arguments: [
        "struct S\nstruct S(var a: Int)", "struct S\nfunc S() {}", "func S() {}\nstruct S",
    ])
    func names(declarations: String) {
        let source = "func main() {}\n" + declarations
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.alreadyDeclared(name: "S")])
        #expect(reported.map(\.range.start.line) == [3])
    }

    @Test("'_' can't name a struct")
    func underscore() {
        #expect(errors("func main() {}\nstruct _") == [.underscoreDeclared])
    }

    @Test("a struct can't contain itself, through its fields at any depth, and each struct in the cycle is an error",
          arguments: [
        ("struct C(var next: C)", ["C"]),
        ("struct A(var b: B)\nstruct B(var a: A)", ["A", "B"]),
        ("struct A(var b: B)\nstruct B(var c: C)\nstruct C(var b: B)", ["B", "C"]),
    ])
    func containsItself(declarations: String, names: [String]) {
        #expect(errors("func main() {}\n" + declarations) == names.map { .containsItself(name: $0) })
    }

    @Test("a struct's name is a type, which a call calls for its initializer", arguments: [
        ("let x = S", ErrorCode.typeAsValue(name: "S")),
        ("S = 1", .assignToType(name: "S")),
        ("let s = S(1)", .argumentLabel(expected: .label("a"), found: .none)),
        ("let s = S(a: true)", .typeMismatch(expected: "Int", found: "Bool")),
        ("let s = S()", .argumentCount(name: "S", takes: 1, passes: 0)),
        ("let e = E(a: 1)", .argumentCount(name: "E", takes: 0, passes: 1)),
        ("let s: E = S(a: 1)", .typeMismatch(expected: "E", found: "S")),
        ("S(a: 1)", .unusedValue(type: "S")),
    ])
    func uses(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}\nstruct S(var a: Int)\nstruct E") == [expected])
    }
}
