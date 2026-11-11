import Foundation
import Testing
import RayoDriver

/// A `rayoc` that no file is, for the commands that stop before they compile.
private let noCompiler = URL(fileURLWithPath: "/nonexistent/rayoc")

struct DriverTests {
    @Test("wrong arguments print the usage", arguments: [
        [], ["check"], ["check", "a.rayo", "b.rayo"], ["parse", "a.rayo"], ["link", "a.rayo"], ["build"],
        ["run", "a.rayo", "b.rayo"],
        ["check", "--debug", "a.rayo"], ["run", "--fast", "a.rayo"], ["run", "a.rayo", "--debug"],
        ["build", "--debug", "--release", "a.rayo"],
        ["check", "--linker=lld", "a.rayo"], ["build", "--linker=lld", "--linker=platform", "a.rayo"],
        ["run", "--linker", "a.rayo"], ["run", "a.rayo", "--linker=lld"],
        ["run", "--linker=bogus"], ["run", "--linker=lld"], ["run", "--linker"], ["run", "--debug"],
        ["build", "--release"], ["check", "--debug"], ["--check", "a.rayo"], ["-o", "a.o", "a.rayo"],
    ])
    func usage(arguments: [String]) {
        let result = Driver.run(arguments, compiler: noCompiler)
        #expect(result.exitCode == 2)
        #expect(result.output == "")
        #expect(result.errors.hasPrefix("usage: rayo <command> <file>\n"))
    }

    @Test("a linker rayo doesn't know is rejected", arguments: ["gold", "", "LLD"])
    func unknownLinker(name: String) {
        #expect(Driver.run(["build", "--linker=\(name)", "a.rayo"], compiler: noCompiler) == CommandResult(
            exitCode: 2, output: "", errors: "rayo: unknown linker '\(name)': use --linker=lld or --linker=platform\n"))
    }

    @Test("a command that has to compile fails without its rayoc", arguments: ["check", "build", "run"])
    func compilerMissing(command: String) {
        #expect(Driver.run([command, "a.rayo"], compiler: noCompiler) ==
            CommandResult(exitCode: 1, output: "", errors: "rayo: can't find rayoc at '/nonexistent/rayoc'\n"))
    }

    @Test(arguments: [
        ("func main() {}", CommandResult(exitCode: 0, output: "", errors: "")),
        ("func f() {\n    let = 1\n}", CommandResult(
            exitCode: 1, output: "", errors: "main.rayo:2:9: error[E0113]: expected a name to bind, found '='\n")),
    ])
    func `check ends as rayoc's check of the file ends, with rayoc's errors`(
        source: String, expected: CommandResult,
    ) throws {
        try withTemporaryDirectory { directory in
            try Data(source.utf8).write(to: directory.appendingPathComponent("main.rayo"))
            #expect(rayo(["check", "main.rayo"], in: directory) == expected)
        }
    }

    @Test func `a file rayoc can't read fails the command with rayoc's error`() throws {
        try withTemporaryDirectory { directory in
            #expect(rayo(["run", "missing.rayo"], in: directory) ==
                CommandResult(exitCode: 1, output: "", errors: "rayoc: can't read 'missing.rayo'\n"))
        }
    }

    @Test(arguments: [
        ([:], "/tools/bin/rayoc"), (["RAYOC": ""], "/tools/bin/rayoc"), (["RAYOC": "/other/rayoc"], "/other/rayoc"),
    ])
    func `rayo compiles with the rayoc that RAYOC names, or else the one beside it`(
        environment: [String: String], expected: String,
    ) {
        let compiler = Driver.compiler(in: environment, besides: URL(fileURLWithPath: "/tools/bin/rayo"))
        #expect(compiler.path == expected)
    }
}
