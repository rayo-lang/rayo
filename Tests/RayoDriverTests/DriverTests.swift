import Foundation
import Testing
import RayoDriver
import RayoLLVMInstall
import ToolStandIn

/// A `rayoc` that no file is: the commands that stop before they compile never run it, and the others fail without it.
private let noCompiler = URL(fileURLWithPath: "/nonexistent/rayoc")

/// Installs a `rayoc` in `directory` that writes "rayoc: a note" to its standard error, then compiles as the built
/// `rayoc` does, and returns it.
private func notingCompiler(in directory: URL) throws -> URL {
    let standIn = ToolStandIn([.write("rayoc: a note\n")], then: .handOff(toToolAt: builtProduct("rayoc")))
    return try install(standIn, as: "rayoc", in: directory)
}

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
            CommandResult(exitCode: 1, output: "", errors: "rayo: can't find rayoc at '\(noCompiler.path)'\n"))
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
            let compiler = try notingCompiler(in: directory)
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
            let compiler = try notingCompiler(in: directory)
            let clang = directory.appendingPathComponent("nonexistent")
            let linkTools = LinkTools(clang: clang, lld: LinkTools.installed.lld)
            #expect(Driver.run([command, source], compiler: compiler, linkTools: linkTools) == CommandResult(
                exitCode: 1, output: "", errors: "rayoc: a note\nrayo: can't find clang at '\(clang.path)'\n"))
        }
    }

    // Windows ends a process by an exception, not a signal.
    #if os(Windows)
    @Test(arguments: ["check", "build", "run"])
    func `a rayoc that an exception ends fails the command with the exception's code, and says which it was`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            // A stand-in can't raise an access violation, but exiting with its code, 0xC0000005, ends it the same
            // way as Windows reports it.
            let accessViolation = Int32(bitPattern: 0xC000_0005)
            let compiler = try install(ToolStandIn([.write("rayoc: started\n")], then: .exit(accessViolation)),
                                       as: "rayoc", in: directory)
            #expect(Driver.run([command, source], compiler: compiler) == CommandResult(
                exitCode: accessViolation, output: "",
                errors: "rayoc: started\nrayo: rayoc crashed with exception 0xC0000005\n"))
        }
    }

    @Test(arguments: ["check", "build", "run"])
    func `a rayoc that exits with a negative code fails the command with that code, as an exit and not a crash`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let compiler = try install(ToolStandIn([.write("rayoc: started\n")], then: .exit(-1)),
                                       as: "rayoc", in: directory)
            #expect(Driver.run([command, source], compiler: compiler) ==
                CommandResult(exitCode: -1, output: "", errors: "rayoc: started\n"))
        }
    }

    @Test(arguments: ["check", "build", "run"])
    func `a rayoc that Ctrl-C ends fails the command with Ctrl-C's code, and says it was interrupted`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            // Windows ends a process by Ctrl-C with the exit code 0xC000013A, which exiting with it gives as well.
            let interrupted = Int32(bitPattern: 0xC000_013A)
            let compiler = try install(ToolStandIn([.write("rayoc: started\n")], then: .exit(interrupted)),
                                       as: "rayoc", in: directory)
            #expect(Driver.run([command, source], compiler: compiler) == CommandResult(
                exitCode: interrupted, output: "", errors: "rayoc: started\nrayo: rayoc was interrupted\n"))
        }
    }

    @Test func `Ctrl-C ends the rayoc that rayo runs and not rayo, which removes its temporary files`() throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() {}", as: "main.rayo", in: directory)
            let compiler = try install(ToolStandIn([], then: .interruptConsole), as: "rayoc", in: directory)
            let temporary = directory.appendingPathComponent("temporary", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

            // `rayo` keeps its temporary files where TMP names, and compiles with the `rayoc` that RAYOC names.
            let environment = ProcessInfo.processInfo.environment
                .setting("TMP", to: temporary.path).setting("TEMP", to: temporary.path)
                .setting("RAYOC", to: compiler.path)
            #expect(try rayoOnConsoleOfItsOwn(["run", "main.rayo"], in: directory, environment: environment) ==
                0xC000_013A)
            #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path) == [])
        }
    }
    #else
    @Test(arguments: ["check", "build", "run"])
    func `a rayoc that a signal ends fails the command, as a shell reports it, with how rayoc ended`(
        command: String,
    ) throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let compiler = try install(ToolStandIn([.write("rayoc: started\n")], then: .signal(9)),
                                       as: "rayoc", in: directory)
            #expect(Driver.run([command, source], compiler: compiler) == CommandResult(
                exitCode: 128 + 9, output: "", errors: "rayoc: started\nrayo: rayoc was ended by signal 9\n"))
        }
    }
    #endif

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
        ([:], "/tools/bin/" + Executable.fileName("rayoc")),
        (["RAYOC": ""], "/tools/bin/" + Executable.fileName("rayoc")),
        (["RAYOC": "/other/rayoc"], "/other/rayoc"),
    ])
    func `rayo compiles with the rayoc that RAYOC names, or else the one beside it`(
        environment: [String: String], expected: String,
    ) {
        let compiler = Driver.compiler(in: environment, beside: URL(fileURLWithPath: "/tools/bin/rayo"))
        #expect(compiler.path == expected)
    }
}
