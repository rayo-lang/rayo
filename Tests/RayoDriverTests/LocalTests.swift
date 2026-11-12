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
