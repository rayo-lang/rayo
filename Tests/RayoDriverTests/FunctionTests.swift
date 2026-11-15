import Testing
import RayoDriver
import RayoRuntime

struct FunctionTests {
    @Test("a call runs a function declared after it, and gives what the function returns")
    func callBeforeDeclaration() {
        #expect(run("func main() { print(answer()) }\nfunc answer() -> Int { 42 }") ==
            CommandResult(exitCode: 0, output: "42\n", errors: ""))
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
}
