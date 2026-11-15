import Testing
import RayoDriver
import RayoRuntime

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

    @Test("a local may share a function's name: a call reaches the function, and every other use the local")
    func sharesFunctionName() {
        #expect(output("""
            var print: Int
            print = 3
            print += 2
            print(print)
            let main = copy print
            print(main + 1)
            """) == "5\n6\n")
    }

    @Test("'copy' gives a local's value, and leaves the local as it was")
    func copies() {
        #expect(output("var a = 1\nlet b = copy a\na = 2\nvar c: Int\nc = copy b\nprint(a + b + c)") == "4\n")
    }

    @Test("'copy' makes its value where the source writes it, before a later operand or argument changes the place")
    func copiesWhereWritten() {
        let result = run("""
            struct P(var hp: Int)
            func show(_ a: P, _ b: Int) { print(a.hp) }
            func main() {
                var x = 1
                let y = (copy x) + if true { x = 10; 1 } else { 2 }
                print(y)
                print(x)
                var p = P(hp: 1)
                show(copy p, if true { p.hp = 7; 0 } else { 0 })
                print(p.hp)
            }
            """)
        #expect(result == CommandResult(exitCode: 0, output: "2\n10\n1\n7\n", errors: ""))
    }

    @Test("a value assigned after a 'copy' of the place, by a later operand, is never read by that copy")
    func assignmentAfterCopyIsUnread() {
        let source = "func main() {\n    var x = 1\n    print((copy x) + if true { x = 10; 1 } else { 2 })\n}"
        let errors = "main.rayo:3:32: error[E0308]: the value assigned to 'x' is never read\n"
        #expect(run(source) == CommandResult(exitCode: 1, output: "", errors: errors))
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
        #expect(run("func main() {\n    var x = 1\n    var zero = 0\n    x /= zero\n    print(x)\n}") == CommandResult(
            exitCode: ProgramRuntime.panicExitCode, output: "", errors: "main.rayo:4:5: panic: division by zero\n"))
    }
}
