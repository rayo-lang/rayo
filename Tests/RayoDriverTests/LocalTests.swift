import Testing
import RayoDiagnostics
import RayoDriver
import RayoRuntime

/// The error for adding a Bool to an Int, as in `1 + true`.
private let intAndBool = ErrorCode.operandTypes(op: "+", needs: "Int", left: "Int", right: "Bool")

struct LocalTests {
    @Test("locals hold values, and a 'var' changes by assignment and compound assignment")
    func locals() {
        #expect(output("""
            let a = 6
            var b: Int = a * 7
            b -= 2
            b = b + 1
            print(b)
            """) == "41\n")
    }

    @Test("a block's locals are visible only inside it")
    func scopes() {
        #expect(errors("func main() {\n    if true { let x = 1 }\n    print(x)\n}") == [.notDeclared(name: "x")])
    }

    @Test("locals are checked", arguments: [
        ("let x = 1\nx = 2", ErrorCode.letAssignedTwice(name: "x")),
        ("let x = 1\nx += 2", .letAssignedTwice(name: "x")),
        ("let x: Bool = 1", .typeMismatch(expected: "Bool", found: "Int")),
        ("var x = 1\nx = true", .typeMismatch(expected: "Int", found: "Bool")),
        ("var x = true\nx += 1", .operandTypes(op: "+=", needs: "Int", left: "Bool", right: "Int")),
        ("1 = 2", .assignToNonLocal),
        ("let x = 1\nlet x = 2", .alreadyDeclared(name: "x")),
        ("let x = print(1)", .voidLocal),
        ("let x = 1\nx(2)", .notAFunction(name: "x")),
        ("print = 3", .assignToFunction(name: "print")),
        ("main += 2", .assignToFunction(name: "main")),
        ("_ += 1", .assignToNonLocal),
        ("print(_)", .underscoreValue),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("a local may share a function's name: a call reaches the function, and every other use the local")
    func sharesFunctionName() {
        #expect(output("""
            var print = 1
            print = 3
            print += 2
            print(print)
            let main = copy print
            print(main + 1)
            """) == "5\n6\n")
    }

    @Test("'copy' copies a local that it names", arguments: [
        ("let b = copy 1", ErrorCode.missingCopiedName(found: .token("1"))),
        ("let b = copy print", .functionAsValue(name: "print")),
        ("let b = copy nope", .notDeclared(name: "nope")),
        ("let b = copy _", .underscoreValue),
    ])
    func copiedName(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("'copy' gives a local's value, and leaves the local as it was")
    func copies() {
        #expect(output("var a = 1\nlet b = copy a\na = 2\nvar c = 0\nc = copy b\nprint(a + b + c)") == "4\n")
    }

    @Test("a declaration that fails still declares its name, so its uses report nothing more", arguments: [
        ("let x = undefined\nprint(x)", ErrorCode.notDeclared(name: "undefined")),
        ("let f = undefined\nf(1)", .notDeclared(name: "undefined")),
        ("let y: Bool = 1\nif y { }", .typeMismatch(expected: "Bool", found: "Int")),
        ("let w: Int8 = 3\nw += 1", .notAType(name: "Int8")),
        ("let x = 1\nif true {\nlet x = true\nif x { }\n}", .alreadyDeclared(name: "x")),
    ])
    func noCascade(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("a call skips a local or a parameter whose declaration failed, and reaches the functions of its name",
          arguments: [
        ("func main() {\n    let sum = nope\n    let y: Bool = sum(3)\n    sum(true)\n}\n"
            + "func sum(_ x: Int) -> Int { copy x }",
         [ErrorCode.notDeclared(name: "nope"), .typeMismatch(expected: "Bool", found: "Int"),
          .typeMismatch(expected: "Int", found: "Bool")], ["nope", "sum(3)", "true"]),
        ("func main() {}\nfunc f(print: Int8) { print(1, 2) }",
         [.notAType(name: "Int8"), .argumentCount(name: "print", takes: 1, passes: 2)], ["Int8", "print(1, 2)"]),
        ("func main() {\n    let x = 1\n    let x = 2\n    x(1)\n    x(true)\n}\nfunc x(_ a: Int) {}",
         [.alreadyDeclared(name: "x"), .typeMismatch(expected: "Int", found: "Bool")], ["x", "true"]),
    ])
    func callSkipsFailedLocal(source: String, expected: [ErrorCode], covered: [String]) {
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test("an assignment's target and value are checked even when the other fails", arguments: [
        ("nope = 1 + true", [ErrorCode.notDeclared(name: "nope"), intAndBool]),
        ("main = undefined", [.assignToFunction(name: "main"), .notDeclared(name: "undefined")]),
        ("print += 1 + true", [.assignToFunction(name: "print"), intAndBool]),
        ("let k = 1\nk(1 + true)", [.notAFunction(name: "k"), intAndBool]),
        ("nope(2 + false)", [.notDeclared(name: "nope"), intAndBool]),
        ("let w: Int8 = 1 + true", [.notAType(name: "Int8"), intAndBool]),
    ])
    func valueChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }

    @Test("compound assignments apply their operator", arguments: [
        ("var x = 7\nx *= 3\nprint(x)", "21\n"), ("var x = 7\nx /= 2\nprint(x)", "3\n"),
        ("var x = 7\nx %= 4\nprint(x)", "3\n"),
    ])
    func compound(body: String, expected: String) {
        #expect(output(body) == expected)
    }

    @Test("a compound assignment that divides by zero panics at the assignment")
    func compoundPanic() {
        #expect(run("func main() {\n    var x = 1\n    var zero = 0\n    x /= zero\n}") == CommandResult(
            exitCode: ProgramRuntime.panicExitCode, output: "", errors: "main.rayo:4:5: panic: division by zero\n"))
    }
}
