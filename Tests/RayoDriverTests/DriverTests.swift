import Testing
import RayoDriver

/// Runs the driver over files held in memory.
private func run(_ arguments: [String], files: [String: String] = [:]) -> Driver.Result {
    Driver.run(arguments) { files[$0].map { Array($0.utf8) } }
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

    @Test("a file that isn't UTF-8 is an error where its first invalid byte is")
    func notUTF8() {
        let result = Driver.run(["check", "a.rayo"]) { _ in Array("func main() {\n    print(1) // é".utf8) + [0xFF] }
        #expect(result == Driver.Result(exitCode: 1, output: "", errors: "a.rayo:2:18: error: the file isn't valid UTF-8\n"))
    }

    @Test("wrong arguments print the usage", arguments: [
        [], ["parse"], ["parse", "a.rayo", "b.rayo"], ["link", "a.rayo"], ["build"], ["run", "a.rayo", "b.rayo"],
        ["check", "--debug", "a.rayo"], ["run", "--fast", "a.rayo"], ["run", "a.rayo", "--debug"],
        ["build", "--debug", "--release", "a.rayo"],
    ])
    func usage(arguments: [String]) {
        let result = run(arguments, files: ["a.rayo": ""])
        #expect(result.exitCode == 2)
        #expect(result.output == "")
        #expect(result.errors.hasPrefix("usage: rayoc <command> <file>\n"))
    }
}
