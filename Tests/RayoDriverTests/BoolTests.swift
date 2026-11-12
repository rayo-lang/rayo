import Testing
import RayoDriver

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

    @Test(arguments: [["--debug"], ["--release"]])
    func `print writes a Bool as 'true' or 'false' on a line of its own`(mode: [String]) {
        #expect(run("func main() {\n    print(true)\n    print(false)\n}", options: mode) ==
            CommandResult(exitCode: 0, output: "true\nfalse\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `print writes the value of a Bool that a program computes`(mode: [String]) {
        let source = """
            func main() {
                let alive = isAlive(hp: 3)
                print(alive)
                print(!alive)
                print(2 * 3 < 5)
                print(isAlive(hp: 0) || 1 == 1)
            }
            func isAlive(hp: Int) -> Bool { hp > 0 }
            """
        #expect(run(source, options: mode) ==
            CommandResult(exitCode: 0, output: "true\nfalse\nfalse\ntrue\n", errors: ""))
    }
}
