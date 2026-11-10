import Testing
import RayoDriver

struct IntegerTests {
    @Test("main prints the value of an integer expression")
    func printsArithmetic() {
        #expect(run("func main() { print(1 + 2 * 3) }") == Driver.Result(exitCode: 0, output: "7\n", errors: ""))
    }

    @Test("'/' rounds toward zero, '%' takes the dividend's sign, and Int.min % -1 is 0", arguments: [
        ("7 / 2", "3"), ("-7 / 2", "-3"), ("7 / -2", "-3"),
        ("7 % 3", "1"), ("-7 % 3", "-1"), ("7 % -3", "1"),
        ("-9223372036854775808 % -1", "0"),
        ("-9223372036854775808", "-9223372036854775808"),
        ("-(-5)", "5"),
        ("5 / -1", "-5"),
    ])
    func division(expression: String, value: String) {
        for mode in [["--debug"], ["--release"]] {
            #expect(run("func main() { print(\(expression)) }", options: mode) ==
                Driver.Result(exitCode: 0, output: value + "\n", errors: ""))
        }
    }

    @Test("division and remainder by zero panic in every build",
          arguments: [("1 / 0", "division"), ("1 % 0", "remainder")])
    func byZero(expression: String, operation: String) {
        for mode in [["--debug"], ["--release"]] {
            #expect(panic(in: run("func main() { print(\(expression)) }", options: mode)) ==
                Panic(reason: "\(operation) by zero"))
        }
    }

    @Test("in a debug build, overflow panics after the output so far", arguments: [
        "9223372036854775807 + 1",
        "-9223372036854775807 - 2",
        "4611686018427387904 * 2",
        "-9223372036854775808 / -1",
        "-(-9223372036854775807 - 1)",
    ])
    func overflowPanics(expression: String) {
        #expect(panic(in: run("func main() {\n    print(1)\n    print(\(expression))\n}", options: ["--debug"])) ==
            Panic(reason: "integer overflow", output: "1\n"))
    }

    @Test("a build that names no mode is a release build, where overflow wraps", arguments: [
        ("9223372036854775807 + 1", "-9223372036854775808"),
        ("-9223372036854775807 - 2", "9223372036854775807"),
        ("4611686018427387904 * 2", "-9223372036854775808"),
        ("-9223372036854775808 / -1", "-9223372036854775808"),
        ("-(-9223372036854775807 - 1)", "-9223372036854775808"),
    ])
    func overflowWraps(expression: String, value: String) {
        for mode in [[], ["--release"]] {
            #expect(run("func main() { print(\(expression)) }", options: mode) ==
                Driver.Result(exitCode: 0, output: value + "\n", errors: ""))
        }
    }

    @Test("in a release build, arithmetic that overflows at run time wraps")
    func overflowWrapsAtRunTime() {
        // A thousand rounds of x * 3 + 1 are too many for LLVM to unroll and have no closed form it can compute,
        // so the multiplications that overflow run in the executable.
        let source = """
            func main() {
                var x = 1
                var i = 0
                while i < 1000 {
                    x = x * 3 + 1
                    i += 1
                }
                print(x)
            }
            """
        #expect(run(source, options: ["--release"]) ==
            Driver.Result(exitCode: 0, output: "-9141782528521893711\n", errors: ""))
    }

    @Test("a panic names the operation that fails, not the expression around it")
    func nestedPanic() {
        #expect(run("func main() { print(1 + (9223372036854775807 + 1)) }", options: ["--debug"]) == Driver.Result(
            exitCode: Driver.panicExitCode, output: "", errors: "main.rayo:1:25: panic: integer overflow\n"))
    }
}
