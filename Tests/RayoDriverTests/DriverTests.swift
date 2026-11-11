import Foundation
import Testing
import RayoDriver

/// A `rayoc` that no file is: the commands that stop before they compile never run it, and the others fail without it.
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

    @Test(arguments: [("check", ""), ("build", ""), ("run", "1\n")])
    func `what rayoc writes to its standard error comes first in what the command writes, when rayoc compiles the file`(
        command: String, output: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() { print(1) }", as: "main.rayo", in: directory)
            let compiler = try script("echo 'rayoc: a note' >&2\nexec '\(builtProduct("rayoc").path)' \"$@\"",
                                      at: directory.appendingPathComponent("rayoc"))
            #expect(Driver.run([command, source], compiler: compiler) ==
                CommandResult(exitCode: 0, output: output, errors: "rayoc: a note\n"))
        }
    }

    @Test(arguments: ["build", "run"])
    func `what rayoc writes to its standard error comes before why the command stopped after it compiled`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let compiler = try script("echo 'rayoc: a note' >&2\nexec '\(builtProduct("rayoc").path)' \"$@\"",
                                      at: directory.appendingPathComponent("rayoc"))
            let clang = directory.appendingPathComponent("nonexistent")
            let linkTools = LinkTools(clang: clang, lld: LinkTools.installed.lld)
            #expect(Driver.run([command, source], compiler: compiler, linkTools: linkTools) == CommandResult(
                exitCode: 1, output: "", errors: "rayoc: a note\nrayo: can't find clang at '\(clang.path)'\n"))
        }
    }

    @Test(arguments: ["check", "build", "run"])
    func `a rayoc that a signal ends fails the command, as a shell reports it, with how rayoc ended`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let compiler = try script("echo 'rayoc: started' >&2\nkill -KILL $$",
                                      at: directory.appendingPathComponent("rayoc"))
            #expect(Driver.run([command, source], compiler: compiler) == CommandResult(
                exitCode: 128 + 9, output: "", errors: "rayoc: started\nrayo: rayoc was ended by signal 9\n"))
        }
    }

    @Test(arguments: ["-o", "--check", "--"])
    func `a file named like one of rayoc's options is the file the command compiles`(name: String) throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() { print(1) }", as: name, in: directory)
            #expect(rayo(["run", name], in: directory) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
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
        let compiler = Driver.compiler(in: environment, beside: URL(fileURLWithPath: "/tools/bin/rayo"))
        #expect(compiler.path == expected)
    }
}
