import Testing
import RayoDriver
import RayoRuntime

struct ParameterTests {
    @Test("a call passes its arguments to the parameters in order, labeled as the parameters are declared")
    func labels() {
        let source = """
            func main() {
                print(difference(from: 10, take: 3))
                print(scaled(4, by: 5))
            }
            func difference(from a: Int, take b: Int) -> Int { a - b }
            func scaled(_ value: Int, by: Int) -> Int { value * by }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "7\n20\n", errors: ""))
    }

    @Test("functions recurse, directly and through each other, in debug and in release", arguments: [["--debug"], ["--release"]])
    func recursion(mode: [String]) {
        let source = """
            func main() {
                print(fibonacci(20))
                if isEven(7) { print(1) } else { print(0) }
                print(sum(to: 100000))
            }
            func fibonacci(_ n: Int) -> Int {
                if n < 2 { return copy n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }
            func isEven(_ n: Int) -> Bool {
                if n == 0 { return true }
                return isOdd(n - 1)
            }
            func isOdd(_ n: Int) -> Bool { n != 0 && isEven(n - 1) }
            func sum(to n: Int) -> Int {
                if n == 0 { return 0 }
                return n + sum(to: n - 1)
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "6765\n0\n5000050000\n", errors: ""))
    }

    @Test("arguments are evaluated left to right, before the call")
    func evaluationOrder() {
        let source = """
            func main() { print(pair(shown(1), shown(2))) }
            func shown(_ x: Int) -> Int {
                print(copy x)
                return copy x
            }
            func pair(_ a: Int, _ b: Int) -> Int { a * 10 + b }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n2\n12\n", errors: ""))
    }

    @Test("a panic in a function names its place there, whatever its arguments")
    func panicInCallee() {
        let source = "func main() {\n    print(ratio(6, 3))\n    print(ratio(1, 0))\n}\nfunc ratio(_ a: Int, _ b: Int) -> Int {\n    return a / b\n}"
        #expect(run(source) == CommandResult(exitCode: ProgramRuntime.panicExitCode, output: "2\n",
                                             errors: "main.rayo:6:12: panic: division by zero\n"))
    }

    @Test("a keyword can be an argument label")
    func keywordLabels() {
        #expect(run("func main() { print(pick(if: true, else: 2)) }\nfunc pick(if c: Bool, else e: Int) -> Int { copy e }")
            == CommandResult(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test("a parameter may share a function's name, and a use of the name other than a call reaches the parameter")
    func sharesFunctionName() {
        let source = """
            func main() { print(next(41)) }
            func next(_ next: Int) -> Int { copy next + 1 }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "42\n", errors: ""))
    }

    @Test("a call skips a parameter, which can't be called, and reaches the functions of its name")
    func callSkipsParameter() {
        let source = """
            func main() {
                print(sum(3))
                show(print: 7)
            }
            func sum(_ sum: Int) -> Int {
                if sum == 0 { return 0 }
                return sum + sum(sum - 1)
            }
            func show(print: Int) { print(print) }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "6\n7\n", errors: ""))
    }

    @Test("functions may share a name when their labels or parameter types differ, and a call picks the one it fits")
    func overloads() {
        let source = """
            func main() {
                print(kind(5))
                print(kind(true))
                print(kind(of: 5))
                print(kind())
            }
            func kind(_ x: Int) { 1 }
            func kind(_ b: Bool) -> Int { 2 }
            func kind(of x: Int) -> Int { 3 }
            func kind() -> Int { 4 }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n2\n3\n4\n", errors: ""))
    }
}
