import Testing
import RayoDiagnostics
import RayoDriver

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
        ("let x = 1\nx = 2", ErrorCode.assignToLet(name: "x")),
        ("let x = 1\nx += 2", .assignToLet(name: "x")),
        ("let x: Bool = 1", .typeMismatch(expected: "Bool", found: "Int")),
        ("var x = 1\nx = true", .typeMismatch(expected: "Int", found: "Bool")),
        ("var x = true\nx += 1", .operandTypes(op: "+=", needs: "Int", left: "Bool", right: "Int")),
        ("1 = 2", .assignToNonLocal),
        ("let x = 1\nlet x = 2", .alreadyDeclared(name: "x")),
        ("let x = print(1)", .voidLocal),
        ("let x: Int", .missingBindingValue(found: .newline)),
        ("let x = 1\nx(2)", .notAFunction(name: "x")),
        ("let print = 1\nprint(print)", .alreadyDeclared(name: "print")),
        ("let main = 1", .alreadyDeclared(name: "main")),
        ("print = 3", .assignToFunction(name: "print")),
        ("main += 2", .assignToFunction(name: "main")),
        ("let _ = 5", .underscoreDeclared),
        ("_ = 5", .assignToNonLocal),
        ("_ += 1", .assignToNonLocal),
        ("print(_)", .underscoreValue),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("a declaration or an assignment takes a local's value only with 'copy'", arguments: [
        ("var a = 1\nlet b = a", ErrorCode.takenWithoutCopy(name: "a")),
        ("var a = 1\nlet b = (a)", .takenWithoutCopy(name: "a")),
        ("var a = 1\nvar b = 0\nb = a", .takenWithoutCopy(name: "a")),
        ("let b = copy 1", .missingCopiedName(found: .token("1"))),
        ("let b = copy print", .functionAsValue(name: "print")),
        ("let b = copy nope", .notDeclared(name: "nope")),
        ("let b = copy _", .underscoreValue),
    ])
    func moves(body: String, expected: ErrorCode) {
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

    @Test("an assignment's target and value are checked even when the other fails", arguments: [
        ("nope = 1 + true", [ErrorCode.notDeclared(name: "nope"), intAndBool]),
        ("let x = 1\nx = undefined", [.assignToLet(name: "x"), .notDeclared(name: "undefined")]),
        ("let x = 1\nx += 1 + true", [.assignToLet(name: "x"), intAndBool]),
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
        #expect(run("func main() {\n    var x = 1\n    var zero = 0\n    x /= zero\n}") == Driver.Result(
            exitCode: Driver.panicExitCode, output: "", errors: "main.rayo:4:5: panic: division by zero\n"))
    }
}

struct BoolTests {
    @Test("comparisons and logic make Bools", arguments: [
        ("1 < 2", true), ("2 <= 2", true), ("3 > 4", false), ("4 >= 5", false), ("1 == 1", true), ("1 != 1", false),
        ("true == false", false), ("true != false", true), ("!false", true), ("true && false", false),
        ("false || true", true),
    ])
    func logic(expression: String, value: Bool) {
        #expect(output("if \(expression) { print(1) } else { print(0) }") == (value ? "1\n" : "0\n"))
    }

    @Test("'&&' and '||' evaluate their right operand only when the left one doesn't decide")
    func shortCircuit() {
        #expect(output("if false && 1 / 0 == 0 { print(1) }\nif true || 1 / 0 == 0 { print(2) }") == "2\n")
    }

    @Test("operands and conditions are checked", arguments: [
        ("if 1 { }", ErrorCode.typeMismatch(expected: "Bool", found: "Int")),
        ("while 0 { }", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = 1 == true", .operandsDiffer(op: "==", left: "Int", right: "Bool")),
        ("let b = true < false", .operandTypes(op: "<", needs: "Int", left: "Bool", right: "Bool")),
        ("let b = 1 && true", .operandTypes(op: "&&", needs: "Bool", left: "Int", right: "Bool")),
        ("let b = !1", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = -true", .typeMismatch(expected: "Int", found: "Bool")),
        ("let b = print(1) == print(2)", .voidComparison(op: "==")),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }
}

struct LoopTests {
    @Test("'while' repeats while its condition holds; 'continue' skips a pass and 'break' leaves the loop")
    func loops() {
        #expect(output("""
            var i = 0
            var sum = 0
            while true {
                i += 1
                if i % 2 == 0 { continue }
                if i > 9 { break }
                sum += i
            }
            print(sum)
            """) == "25\n")
    }

    @Test("'continue' goes back to the condition, and code after 'continue' or 'break' doesn't run")
    func continueChecksCondition() {
        #expect(output("var i = 0\nwhile i < 3 {\ni += 1\ncontinue\nprint(9)\n}\nprint(i)") == "3\n")
        #expect(output("while true {\nbreak\nprint(1)\n}\nprint(2)") == "2\n")
    }

    @Test("a loop whose condition fails at once never runs its body, and a condition may use '&&'", arguments: [
        ("while false { print(1) }\nprint(2)", "2\n"),
        ("var i = 0\nwhile i < 5 && i != 3 {\ni += 1\n}\nprint(i)", "3\n"),
    ])
    func conditions(body: String, expected: String) {
        #expect(output(body) == expected)
    }

    @Test("a condition that panics stops the loop")
    func conditionPanics() {
        #expect(panic(in: run("func main() {\n    var i = 1\n    while 1 / (i - 1) > 0 { }\n}")) ==
            Panic(reason: "division by zero"))
    }

    @Test("'else if' chains pick the first branch whose condition holds", arguments: [(1, "1\n"), (2, "2\n"), (3, "0\n")])
    func elseIf(value: Int, expected: String) {
        #expect(output("""
            let n = \(value)
            if n == 1 { print(1) } else if n == 2 { print(2) } else { print(0) }
            """) == expected)
    }

    @Test("'break' and 'continue' leave the innermost loop")
    func nested() {
        #expect(output("""
            var i = 0
            while i < 3 {
                i += 1
                var j = 0
                while true {
                    j += 1
                    if j < i { continue }
                    break
                }
                print(j)
            }
            """) == "1\n2\n3\n")
    }

    @Test("'break' and 'continue' need a loop", arguments: ["break", "continue"])
    func outsideLoop(keyword: String) {
        #expect(errors("func main() {\n\(keyword)\n}") == [.outsideLoop(keyword: keyword)])
    }
}
