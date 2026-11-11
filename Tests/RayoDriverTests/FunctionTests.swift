import Testing
import RayoDriver
import RayoRuntime

struct FunctionTests {
    @Test("a call runs a function declared after it, and gives what the function returns")
    func callBeforeDeclaration() {
        #expect(run("func main() { print(answer()) }\nfunc answer() -> Int { 42 }") ==
            CommandResult(exitCode: 0, output: "42\n", errors: ""))
    }

    @Test("'return' leaves the function, with its value when it has one, and code after it doesn't run")
    func returns() {
        let source = """
            func main() {
                report()
                print(double())
            }
            func report() {
                print(1)
                if true { return }
                print(2)
            }
            func double() -> Int {
                var x = 20
                while true {
                    x += 1
                    return x * 2
                }
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n42\n", errors: ""))
    }

    @Test("a function with a result ends every path in 'return', or in a loop that never ends", arguments: [
        "if 1 < 2 { return 1 } else if true { return 2 } else { return 3 }",
        "return 1\nprint(2)",
        "if true { } else { }\nvar i = 0\nwhile (true) {\ni += 1\nif i == 1 { return copy i }\n}",
        "while true {\nwhile true { break }\nif 2 > 1 { return 1 }\n}",
    ])
    func everyPathReturns(body: String) {
        #expect(run("func main() { print(f()) }\nfunc f() -> Int {\n\(body)\n}") ==
            CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("a function without '->' whose body is one expression returns that expression's type")
    func inferredResult() {
        let source = """
            func main() {
                if positive() { print(seven()) }
                say()
            }
            func positive() { seven() > 0 }
            func seven() { 3 + 4 }
            func say() { print(1) }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "7\n1\n", errors: ""))
    }

    @Test("functions may call themselves and each other, in any order")
    func recursion() {
        let source = """
            func main() { print(even()) }
            func even() -> Int {
                if true { return 1 }
                return odd()
            }
            func odd() -> Int { even() }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("a panic in a function names its place in that function")
    func panicInCallee() {
        let source = "func main() {\n    print(1)\n    print(f())\n}\nfunc f() -> Int {\n    return 1 / zero()\n}\nfunc zero() { 0 }"
        #expect(run(source) == CommandResult(exitCode: ProgramRuntime.panicExitCode, output: "1\n",
                                             errors: "main.rayo:6:12: panic: division by zero\n"))
    }

    @Test("functions may take the names of the runtime's functions and of the C functions it calls")
    func runtimeNames() {
        let source = """
            func main() {
                print(printf() + write() + exit() + fflush())
                print(1 / 0)
            }
            func printf() { 1 }
            func write() { 2 }
            func exit() { 3 }
            func fflush() { 4 }
            func print_int() {}
            func panic() {}
            """
        #expect(run(source) == CommandResult(exitCode: ProgramRuntime.panicExitCode, output: "10\n",
                                             errors: "main.rayo:3:11: panic: division by zero\n"))
    }

    @Test("a Void function returns a Void value, and 'return' alone", arguments: [
        "func f() { return print(1) }", "func f() -> () { return }", "func main() { return }",
    ])
    func voidReturns(declaration: String) {
        let source = declaration.hasPrefix("func main") ? declaration : "func main() { f() }\n" + declaration
        #expect(run(source) == CommandResult(exitCode: 0, output: declaration.contains("print") ? "1\n" : "",
                                             errors: ""))
    }
}
