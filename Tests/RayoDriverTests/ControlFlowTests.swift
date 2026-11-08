import Testing
import RayoDriver

/// The output of running `body` as `main`'s body, which must not fail.
private func output(_ body: String) -> String {
    let result = run("func main() {\n\(body)\n}")
    #expect(result.exitCode == 0)
    #expect(result.errors == "")
    return result.output
}

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
        #expect(errors("func main() {\n    if true { let x = 1 }\n    print(x)\n}") ==
            ["3:11: error: 'x' isn't declared"])
    }

    @Test("locals are checked", arguments: [
        ("let x = 1\nx = 2", "3:1: error: 'x' is a 'let', so it can't change"),
        ("let x = 1\nx += 2", "3:1: error: 'x' is a 'let', so it can't change"),
        ("let x: Bool = 1", "2:15: error: expected Bool, found Int"),
        ("var x = 1\nx = true", "3:5: error: expected Int, found Bool"),
        ("var x = true\nx += 1", "3:1: error: '+=' needs Int operands, found Bool and Int"),
        ("1 = 2", "2:1: error: only a place can be assigned"),
        ("let x = 1\nlet x = 2", "3:5: error: declaring 'x' while another 'x' is visible isn't supported yet"),
        ("let x = print(1)", "2:9: error: a value of type Void isn't supported yet"),
        ("let x: Int", "2:1: error: a declaration without a value isn't supported yet"),
        ("let x = borrow y", "2:9: error: 'borrow' isn't supported yet"),
        ("let print = 1\nprint(print)", "3:1: error: 'print' isn't a function"),
    ])
    func rejected(body: String, expected: String) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("a declaration that fails still declares its name, so its uses report nothing more", arguments: [
        ("let x = undefined\nprint(x)", "2:9: error: 'undefined' isn't declared"),
        ("let y: Bool = 1\nif y { }", "2:15: error: expected Bool, found Int"),
        ("let w: Int8 = 3\nw += 1", "2:8: error: the type 'Int8' isn't supported yet"),
        ("let x = 1\nif true {\nlet x = true\nif x { }\n}", "4:5: error: declaring 'x' while another 'x' is visible isn't supported yet"),
    ])
    func noCascade(body: String, expected: String) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }

    @Test("an assignment's value is checked even when its target fails", arguments: [
        ("nope = 1 + true", ["2:1: error: 'nope' isn't declared", "2:8: error: '+' needs Int operands, found Int and Bool"]),
        ("let w: Int8 = 1 + true", ["2:8: error: the type 'Int8' isn't supported yet",
                                     "2:15: error: '+' needs Int operands, found Int and Bool"]),
    ])
    func valueChecked(body: String, expected: [String]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }

    @Test("compound assignments apply their operator, and panic where it fails", arguments: [
        ("var x = 7\nx *= 3\nprint(x)", "21\n"), ("var x = 7\nx /= 2\nprint(x)", "3\n"),
        ("var x = 7\nx %= 4\nprint(x)", "3\n"),
    ])
    func compound(body: String, expected: String) {
        #expect(output(body) == expected)
    }

    @Test("a compound assignment that divides by zero panics at the assignment")
    func compoundPanic() {
        #expect(run("func main() {\n    var x = 1\n    var zero = 0\n    x /= zero\n}") ==
            panicked("4:5: panic: division by zero"))
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
        ("if 1 { }", "2:4: error: expected Bool, found Int"),
        ("while 0 { }", "2:7: error: expected Bool, found Int"),
        ("let b = 1 == true", "2:9: error: '==' needs operands of one type, found Int and Bool"),
        ("let b = true < false", "2:9: error: '<' needs Int operands, found Bool and Bool"),
        ("let b = 1 && true", "2:9: error: '&&' needs Bool operands, found Int and Bool"),
        ("let b = !1", "2:10: error: expected Bool, found Int"),
        ("let b = -true", "2:10: error: expected Int, found Bool"),
        ("let b = print(1) == print(2)", "2:9: error: '==' can't compare Void values"),
    ])
    func rejected(body: String, expected: String) {
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

    @Test("'continue' goes back to the condition")
    func continueChecksCondition() {
        #expect(output("var i = 0\nwhile i < 3 {\ni += 1\ncontinue\n}\nprint(i)") == "3\n")
    }

    @Test("'else if' chains pick the first branch whose condition holds", arguments: [(1, "one"), (2, "two"), (3, "other")])
    func elseIf(value: Int, expected: String) {
        let codes = ["one": 1, "two": 2, "other": 0]
        #expect(output("""
            let n = \(value)
            if n == 1 { print(1) } else if n == 2 { print(2) } else { print(0) }
            """) == "\(codes[expected]!)\n")
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
                    if j == i { break }
                }
                print(j)
            }
            """) == "1\n2\n3\n")
    }

    @Test("'break' and 'continue' need a loop", arguments: ["break", "continue"])
    func outsideLoop(keyword: String) {
        #expect(errors("func main() {\n\(keyword)\n}") == ["2:1: error: '\(keyword)' is only allowed inside a loop"])
    }
}
