import Testing
import RayoDriver

/// The source of a program whose `main` prints what `expression` gives on the UInts `a` and `b`, which it takes from
/// parameters, so no build computes the expression before the program runs.
private func printing(_ expression: String, a: String, b: String = "0") -> String {
    """
    func main() { show(\(a), \(b)) }
    func show(_ a: UInt, _ b: UInt) { print(\(expression)) }
    """
}

struct UIntTests {
    @Test func `'print' writes a UInt in decimal, UInt.max too`() {
        #expect(output("let u: UInt = 18446744073709551615\nprint(u)") == "18446744073709551615\n")
    }

    @Test func `a UInt is a local, a parameter, a result and a field`() {
        let source = """
            struct Counter(var count: UInt)
            func main() {
                var c = Counter(count: 1)
                c.count = next(copy c.count)
                let total: UInt = copy c.count
                print(total)
            }
            func next(_ n: UInt) -> UInt { n + 1 }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test(arguments: [
        ("a + b", "18446744073709551615", "0", "18446744073709551615"),
        ("a - b", "18446744073709551615", "18446744073709551614", "1"),
        ("a * b", "9223372036854775807", "2", "18446744073709551614"),
        ("a / b", "18446744073709551615", "2", "9223372036854775807"),
        ("a % b", "18446744073709551615", "10", "5"),
        ("-a", "0", "0", "0"),
        ("a < b", "1", "18446744073709551615", "true"),
        ("a <= b", "18446744073709551615", "18446744073709551615", "true"),
        ("a > b", "18446744073709551615", "1", "true"),
        ("a >= b", "0", "18446744073709551615", "false"),
        ("a == b", "18446744073709551615", "18446744073709551615", "true"),
        ("a != b", "0", "18446744073709551615", "true"),
    ])
    func `each operator on UInts gives the UInt or Bool it names, at 0 and UInt.max too`(
        expression: String, a: String, b: String, value: String,
    ) {
        for mode in [["--debug"], ["--release"]] {
            #expect(run(printing(expression, a: a, b: b), options: mode) ==
                CommandResult(exitCode: 0, output: value + "\n", errors: ""))
        }
    }

    @Test(arguments: [
        ("a - b", "0", "1", "18446744073709551615"),
        ("a + b", "18446744073709551615", "1", "0"),
        ("a * b", "9223372036854775808", "2", "0"),
        ("-a", "1", "0", "18446744073709551615"),
    ])
    func `an overflowing UInt operation panics in a debug build, and wraps in a release build`(
        expression: String, a: String, b: String, wrapped: String,
    ) {
        #expect(panic(in: run(printing(expression, a: a, b: b), options: ["--debug"])) ==
            Panic(reason: "integer overflow"))
        #expect(run(printing(expression, a: a, b: b), options: ["--release"]) ==
            CommandResult(exitCode: 0, output: wrapped + "\n", errors: ""))
    }

    @Test(arguments: [("a / b", "division"), ("a % b", "remainder")])
    func `UInt division and remainder by zero panic in every build`(expression: String, operation: String) {
        for mode in [["--debug"], ["--release"]] {
            let result = run(printing(expression, a: "1"), options: mode)
            #expect(panic(in: result) == Panic(reason: "\(operation) by zero"))
        }
    }

    @Test(arguments: [
        ("i: Int", "UInt(i)", "9223372036854775807"),
        ("u: UInt", "Int(u)", "9223372036854775807"),
        ("i: Int", "UInt(i)", "0"),
    ])
    func `a conversion between Int and UInt keeps a value that fits`(
        parameter: String, expression: String, value: String,
    ) {
        let source = "func main() { show(\(value)) }\nfunc show(_ \(parameter)) { print(\(expression)) }"
        for mode in [["--debug"], ["--release"]] {
            #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: value + "\n", errors: ""))
        }
    }

    @Test(arguments: [
        ("i: Int", "UInt(i)", "-1", "18446744073709551615"),
        ("u: UInt", "Int(u)", "18446744073709551615", "-1"),
        ("i: Int", "UInt(i)", "-9223372036854775808", "9223372036854775808"),
        ("u: UInt", "Int(u)", "9223372036854775808", "-9223372036854775808"),
    ])
    func `a conversion of a value the other type can't hold panics in debug, and keeps its bits in release`(
        parameter: String, expression: String, value: String, bits: String,
    ) {
        let source = "func main() { show(\(value)) }\nfunc show(_ \(parameter)) { print(\(expression)) }"
        #expect(panic(in: run(source, options: ["--debug"])) == Panic(reason: "integer overflow"))
        #expect(run(source, options: ["--release"]) == CommandResult(exitCode: 0, output: bits + "\n", errors: ""))
    }

    @Test func `a UInt moves and copies as an Int does`() {
        let source = """
            struct Pair(var a: UInt, var b: UInt)
            func main() {
                let p = Pair(a: 1, b: 2)
                let q = p
                let n = copy q.a
                print(n + q.b)
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "3\n", errors: ""))
    }
}
