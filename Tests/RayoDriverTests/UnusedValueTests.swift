import Testing
import RayoDriver

struct UnusedValueTests {
    @Test("'_ =' drops a value on purpose, which is still computed")
    func dropped() {
        let source = """
            func main() {
                _ = say(1)
                _ = print(2)
                let x = 3
                _ = copy x
            }
            func say(_ x: Int) -> Int {
                print(x)
                return copy x
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n2\n", errors: ""))
    }

    @Test("computing a dropped value still panics", arguments: [
        ("let z = 0\n_ = 1 / z", ["--release"], "division by zero"),
        ("let z = 0\n_ = 1 % z", ["--release"], "remainder by zero"),
        ("let big = 9223372036854775807\n_ = big + 1", ["--debug"], "integer overflow"),
    ])
    func droppedPanics(body: String, mode: [String], reason: String) {
        #expect(panic(in: run("func main() {\n\(body)\n}", options: mode)) == Panic(reason: reason))
    }
}
