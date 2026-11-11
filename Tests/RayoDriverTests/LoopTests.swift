import Testing

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

    @Test("'else if' chains pick the first branch whose condition holds",
          arguments: [(1, "1\n"), (2, "2\n"), (3, "0\n")])
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
}
