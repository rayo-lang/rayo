import Testing
import RayoDiagnostics
import RayoDriver

/// Runs the driver over files held in memory.
private func run(_ arguments: [String], files: [String: String] = [:]) -> RunResult {
    Driver.run(arguments) { files[$0].map { Array($0.utf8) } }
}

struct CommandLineTests {
    @Test("errors fail the run, and go to the error stream as the file's path, the position, the code and the message")
    func errorFormat() {
        let result = run(["check", "a.rayo"], files: ["a.rayo": "func f() {\n    let = 1\n    x = )\n}"])
        #expect(result.exitCode == 1)
        #expect(result.output == "")
        #expect(result.diagnostics.map(\.code) == [
            .missingBindingName(found: .token("=")), .missingExpression(found: .token(")")),
        ])
        #expect(result.errors == """
            a.rayo:2:9: error[E0113]: expected a name to bind, found '='
            a.rayo:3:9: error[E0115]: expected an expression, found ')'

            """)
    }

    @Test("a file that can't be read fails the run")
    func unreadable() {
        #expect(run(["check", "missing.rayo"]) ==
            RunResult(exitCode: 1, output: "", errors: "rayoc: can't read 'missing.rayo'\n"))
    }

    @Test("a file that isn't UTF-8 is an error")
    func notUTF8() {
        let result = Driver.run(["check", "a.rayo"]) { _ in Array("func main() {\n    print(1) // é".utf8) + [0xFF] }
        #expect(result.exitCode == 1)
        #expect(result.diagnostics.map(\.code) == [.notUTF8])
    }

    @Test("wrong arguments print the usage", arguments: [
        [], ["check"], ["check", "a.rayo", "b.rayo"], ["parse", "a.rayo"], ["link", "a.rayo"], ["build"],
        ["run", "a.rayo", "b.rayo"],
        ["check", "--debug", "a.rayo"], ["run", "--fast", "a.rayo"], ["run", "a.rayo", "--debug"],
        ["build", "--debug", "--release", "a.rayo"],
        ["check", "--linker=lld", "a.rayo"], ["build", "--linker=lld", "--linker=platform", "a.rayo"],
        ["run", "--linker", "a.rayo"], ["run", "a.rayo", "--linker=lld"],
        ["run", "--linker=bogus"], ["run", "--linker=lld"], ["run", "--linker"], ["run", "--debug"],
        ["build", "--release"], ["check", "--debug"],
    ])
    func usage(arguments: [String]) {
        let result = run(arguments, files: ["a.rayo": ""])
        #expect(result.exitCode == 2)
        #expect(result.output == "")
        #expect(result.errors.hasPrefix("usage: rayoc <command> <file>\n"))
    }

    @Test("a linker rayoc doesn't know is rejected", arguments: ["gold", "", "LLD"])
    func unknownLinker(name: String) {
        let errors = "rayoc: unknown linker '\(name)': use --linker=lld or --linker=platform\n"
        #expect(run(["build", "--linker=\(name)", "a.rayo"], files: ["a.rayo": ""])
            == RunResult(exitCode: 2, output: "", errors: errors))
    }
}
