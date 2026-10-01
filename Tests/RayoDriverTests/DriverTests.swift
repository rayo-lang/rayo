import Testing
import RayoDriver

/// Runs the driver over files held in memory.
private func run(_ arguments: [String], files: [String: String] = [:]) -> Driver.Result {
    Driver.run(arguments) { files[$0] }
}

struct DriverTests {
    @Test("parse prints the syntax tree")
    func parse() {
        let result = run(["parse", "a.rayo"], files: ["a.rayo": "func f() { x = 1 }"])
        #expect(result == Driver.Result(exitCode: 0, output: "(func f() {(= x 1)})\n", errors: ""))
    }

    @Test("syntax errors go to the error stream, after the file's path, and fail the run")
    func syntaxErrors() {
        let result = run(["parse", "a.rayo"], files: ["a.rayo": "func f() {\n    let = 1\n    x = )\n}"])
        #expect(result == Driver.Result(exitCode: 1, output: "", errors: """
            a.rayo:2:9: error: expected a name to bind, found '='
            a.rayo:3:9: error: expected an expression, found ')'

            """))
    }

    @Test("a file that can't be read fails the run")
    func unreadable() {
        #expect(run(["parse", "missing.rayo"]) ==
            Driver.Result(exitCode: 1, output: "", errors: "rayoc: can't read 'missing.rayo'\n"))
    }

    @Test("wrong arguments print the usage", arguments: [
        [], ["parse"], ["parse", "a.rayo", "b.rayo"], ["build", "a.rayo"], ["build", "missing.rayo"],
    ])
    func usage(arguments: [String]) {
        let result = run(arguments, files: ["a.rayo": ""])
        #expect(result.exitCode == 2)
        #expect(result.output == "")
        #expect(result.errors.hasPrefix("usage: rayoc <command> <file>\n"))
    }
}
