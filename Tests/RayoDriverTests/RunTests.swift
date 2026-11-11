import Foundation
import Testing
import RayoDriver
import RayoLLVMInstall
import RayoRuntime
import ToolStandIn

/// The `rayoc` that the tests that run `rayo` in this process compile with.
private let compiler = builtProduct("rayoc")

/// Compiles `source`, saved as `main.rayo` in a directory of its own, in the build mode `options` name, and runs
/// it, with `rayo run` in that directory. A source that can't be saved is recorded as an issue, and gives exit
/// code -1.
func run(_ source: String, options: [String] = []) -> CommandResult {
    do {
        return try withTemporaryDirectory { directory in
            _ = try save(source, as: "main.rayo", in: directory)
            return rayo(["run"] + options + ["main.rayo"], in: directory)
        }
    } catch {
        Issue.record(error)
        return CommandResult(exitCode: -1, output: "", errors: "")
    }
}

/// The output of running `body` as `main`'s body, which must not fail.
func output(_ body: String) -> String {
    let result = run("func main() {\n\(body)\n}")
    #expect(result.exitCode == 0)
    #expect(result.errors == "")
    return result.output
}

/// A run that panicked: the reason it gave, and the output written before it.
struct Panic: Equatable {
    var reason: String
    var output = ""
}

/// The panic `result` reports in `path`, at any line and column; nil unless the error stream is exactly that one
/// panic's line and the exit code is a panic's.
func panic(in result: CommandResult, file path: String = "main.rayo") -> Panic? {
    guard result.exitCode == ProgramRuntime.panicExitCode, result.errors.hasPrefix(path + ":"),
          result.errors.hasSuffix("\n") else { return nil }
    let line = result.errors.dropFirst(path.count + 1).dropLast()
    let fields = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
    guard !line.contains("\n"), fields.count == 4, fields[0..<2].allSatisfy(isNumeral), fields[2] == " panic",
          fields[3].hasPrefix(" ") else { return nil }
    return Panic(reason: String(fields[3].dropFirst()), output: result.output)
}

private func isNumeral(_ text: Substring) -> Bool {
    !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
}

/// Runs an empty `main`, linked with `linkTools` in the way `options` name.
private func runEmptyMain(options: [String] = [], linkTools: LinkTools) throws -> CommandResult {
    try withTemporaryDirectory { directory in
        let source = try save("func main() {}", as: "main.rayo", in: directory)
        return Driver.run(["run"] + options + [source], compiler: compiler, linkTools: linkTools)
    }
}

/// What `executable` writes to its standard output when run with `arguments`, once it exits with 0.
private func runExecutable(_ executable: URL, arguments: [String] = []) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let written = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return written
}

/// The environment these tests run in, with `directory` first on its search path.
private func environment(searchingFirst directory: URL) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    #if os(Windows)
    // Windows reads an environment variable's name in any case, and its own name for the search path is `Path`.
    let name = environment.keys.first { $0.uppercased() == "PATH" } ?? "Path"
    let separator = ";"
    #else
    let name = "PATH"
    let separator = ":"
    #endif
    environment[name] = directory.path + separator + environment[name, default: ""]
    return environment
}

/// The symbols `executable` exports, as the LLVM install's tools list them.
private func symbols(exportedBy executable: URL) throws -> [String] {
    #if os(Windows)
    // An executable's export table lists each symbol it exports by its name.
    return try values(of: "Name", in: executable, listedBy: "--coff-exports")
    #else
    // Each line of the symbol table ends in a symbol's name.
    let arguments = ["--extern-only", "--defined-only", executable.path]
    let listing = try runExecutable(llvmTool("llvm-nm"), arguments: arguments)
    return listing.split(whereSeparator: \.isNewline).compactMap { $0.split(separator: " ").last.map(String.init) }
    #endif
}

/// The values of each `field` that the LLVM install's `llvm-readobj`, given `option`, lists for `executable`.
private func values(of field: String, in executable: URL, listedBy option: String) throws -> [String] {
    // `llvm-readobj` lists each field on a line of its own, indented, as its name, `: ` and its value.
    let listing = try runExecutable(llvmTool("llvm-readobj"), arguments: [option, executable.path])
    return listing.split(whereSeparator: \.isNewline).compactMap { line in
        let entry = line.drop { $0 == " " }
        return entry.hasPrefix(field + ": ") ? String(entry.dropFirst(field.count + 2)) : nil
    }
}

/// The LLVM install's tool `name`.
private func llvmTool(_ name: String) -> URL {
    URL(fileURLWithPath: LLVMInstall.toolDirectory).appendingPathComponent(Executable.fileName(name))
}

struct BuildTests {
    @Test("build writes an executable beside the source, named after it")
    func build() throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() { print(42) }", as: "answer.rayo", in: directory)
            #expect(rayo(["build", "answer.rayo"], in: directory) == CommandResult(exitCode: 0, output: "", errors: ""))

            #expect(try runExecutable(directory.appendingPathComponent(Executable.fileName("answer"))) == "42\n")
        }
    }

    @Test("build needs a name before '.rayo', so the executable can't replace the source", arguments: [
        ("answer", "'answer' doesn't end in '.rayo'"),
        ("dir/.rayo", "'dir/.rayo' has no name before '.rayo'"),
        ("dir/..rayo", "'dir/..rayo' has no name before '.rayo'"),
        ("dir/...rayo", "'dir/...rayo' has no name before '.rayo'"),
    ])
    func nameRequired(path: String, message: String) {
        // No file exists at the path, so a check that let the path through would fail without writing anything.
        #expect(Driver.run(["build", path], compiler: compiler) ==
            CommandResult(exitCode: 1, output: "", errors: "rayo: \(message)\n"))
    }

    @Test("build and run need the clang of the LLVM install, and a directory named clang isn't one")
    func clangMissing() throws {
        try withTemporaryDirectory { directory in
            let decoy = directory.appendingPathComponent("clang")
            try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
            for clang in [directory.appendingPathComponent("nonexistent"), decoy] {
                let tools = LinkTools(clang: clang, lld: LinkTools.installed.lld)
                #expect(try runEmptyMain(linkTools: tools) ==
                    CommandResult(exitCode: 1, output: "", errors: "rayo: can't find clang at '\(clang.path)'\n"))
            }
        }
    }

    @Test("a clang that fails has its errors reported")
    func clangFails() throws {
        try withTemporaryDirectory { directory in
            let clang = try install(ToolStandIn([.write("clang: something broke\n")], then: .exit(1)),
                                    as: "clang", in: directory)
            let tools = LinkTools(clang: clang, lld: LinkTools.installed.lld)
            #expect(try runEmptyMain(linkTools: tools) ==
                CommandResult(exitCode: 1, output: "", errors: "rayo: clang failed:\nclang: something broke\n"))
        }
    }

    @Test("rayoc compiles the program itself, and clang only links it")
    func clangOnlyLinks() throws {
        try withTemporaryDirectory { directory in
            // Hands what it is given to the installed clang, unless it is source clang would compile.
            let standIn = ToolStandIn([.refuseArguments(endingIn: [".ll", ".bc", ".c", ".s"])],
                                      then: .handOff(toToolAt: LinkTools.installed.clang))
            let clang = try install(standIn, as: "clang", in: directory)
            let tools = LinkTools(clang: clang, lld: LinkTools.installed.lld)
            let source = try save("func main() { print(42) }", as: "main.rayo", in: directory)
            let result = Driver.run(["run", source], compiler: compiler, linkTools: tools)
            #expect(result == CommandResult(exitCode: 0, output: "42\n", errors: ""))
        }
    }

    @Test("each linker links an executable that runs, and LLD links unless the platform's linker is asked for",
          arguments: [(["--linker=lld"], true), (["--linker=platform"], false), ([], true)])
    func linkers(options: [String], linksWithLLD: Bool) throws {
        try withTemporaryDirectory { directory in
            // Records that it ran, and hands what it is given to the installed LLD.
            let ran = directory.appendingPathComponent("lld-ran")
            let standIn = ToolStandIn([.touch(ran)], then: .handOff(toToolAt: LinkTools.installed.lld))
            // clang on Windows finds LLD by its name, `lld-link`, in the directory `rayo` names.
            #if os(Windows)
            let lld = try install(standIn, as: "lld-link", in: directory)
            #else
            let lld = try install(standIn, as: "lld", in: directory)
            #endif
            let source = try save("func main() { print(42) }", as: "answer.rayo", in: directory)
            let tools = LinkTools(clang: LinkTools.installed.clang, lld: lld)
            let result = Driver.run(["build"] + options + [source], compiler: compiler, linkTools: tools)
            #expect(result == CommandResult(exitCode: 0, output: "", errors: ""))
            #expect(try runExecutable(directory.appendingPathComponent(Executable.fileName("answer"))) == "42\n")
            #expect(FileManager.default.fileExists(atPath: ran.path) == linksWithLLD)
        }
    }

    @Test("linking with LLD needs the LLD of the LLVM install, and the platform's linker doesn't")
    func lldMissing() throws {
        // The closure throws only from inside `#expect`, which its type isn't inferred from.
        try withTemporaryDirectory { directory throws in
            let lld = directory.appendingPathComponent("nonexistent", isDirectory: true)
                .appendingPathComponent(Executable.fileName("lld"))
            let tools = LinkTools(clang: LinkTools.installed.clang, lld: lld)
            #expect(try runEmptyMain(linkTools: tools) == CommandResult(exitCode: 1, output: "", errors: """
                rayo: can't find LLD at '\(lld.path)': install LLD 23, run 'swift package purge-cache' and \
                build rayo again, or link with --linker=platform

                """))
            #expect(try runEmptyMain(options: ["--linker=platform"], linkTools: tools) ==
                CommandResult(exitCode: 0, output: "", errors: ""))
        }
    }

    @Test("the platform's linker is the platform's, not a linker of its name first on the search path")
    func platformLinkerIgnoresSearchPath() throws {
        try withTemporaryDirectory { directory in
            #if os(Windows)
            let name = "link"
            #else
            let name = "ld"
            #endif
            let ran = directory.appendingPathComponent("linker-ran")
            _ = try install(ToolStandIn([.touch(ran)], then: .exit(1)), as: name, in: directory)
            let source = try save("func main() { print(42) }", as: "main.rayo", in: directory)
            let result = Driver.run(["run", "--linker=platform", source], compiler: compiler,
                                    environment: environment(searchingFirst: directory))
            #expect(result == CommandResult(exitCode: 0, output: "42\n", errors: ""))
            #expect(!FileManager.default.fileExists(atPath: ran.path))
        }
    }

    @Test(
        "an executable exports nothing of the program or the runtime, and on macOS and Linux exports the C entry point")
    func exportedSymbols() throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() {}", as: "empty.rayo", in: directory)
            #expect(rayo(["build", "empty.rayo"], in: directory) == CommandResult(exitCode: 0, output: "", errors: ""))

            let exported = try symbols(exportedBy: directory.appendingPathComponent(Executable.fileName("empty")))
            #expect(exported.filter { $0.contains("rayo.") } == [])
            #if os(Windows)
            // A Windows executable exports only the functions marked for export, and the C entry point is none.
            #expect(exported == [])
            #else
            #expect(exported.contains { $0 == "main" || $0 == "_main" })
            #endif
        }
    }

    #if os(Windows)
    @Test("on Windows each linker links an executable whose main thread reserves a stack of 16 MiB",
          arguments: [["--linker=lld"], ["--linker=platform"]])
    func stackReserve(options: [String]) throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() {}", as: "empty.rayo", in: directory)
            #expect(rayo(["build"] + options + ["empty.rayo"], in: directory) ==
                CommandResult(exitCode: 0, output: "", errors: ""))

            let executable = directory.appendingPathComponent(Executable.fileName("empty"))
            #expect(try values(of: "SizeOfStackReserve", in: executable, listedBy: "--file-headers") == ["16777216"])
        }
    }
    #endif

    @Test("build builds in the mode it names")
    func buildMode() throws {
        try withTemporaryDirectory { directory in
            _ = try save("func main() { print(9223372036854775807 + 1) }", as: "overflow.rayo", in: directory)
            #expect(rayo(["build", "--debug", "overflow.rayo"], in: directory) ==
                CommandResult(exitCode: 0, output: "", errors: ""))

            let executable = Process()
            executable.executableURL = directory.appendingPathComponent(Executable.fileName("overflow"))
            let errors = Pipe()
            executable.standardError = errors
            try executable.run()
            executable.waitUntilExit()
            let reported = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let result = CommandResult(exitCode: executable.terminationStatus, output: "", errors: reported)
            #expect(panic(in: result, file: "overflow.rayo") == Panic(reason: "integer overflow"))
        }
    }

    @Test("a run whose output is the terminal's ends with the program's exit status")
    func attached() throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() { print(1 / 0) }", as: "main.rayo", in: directory)
            let result = Driver.run(["run", source], compiler: compiler, processOutput: .inherited)
            #expect(result == CommandResult(exitCode: ProgramRuntime.panicExitCode, output: "", errors: ""))
        }
    }

    // Windows ends a process by an exception, not a signal.
    #if os(Windows)
    @Test("a run that an exception ends ends with the exception's code")
    func exception() {
        // A recursion with no end overflows the stack, which Windows reports as the exception 0xC00000FD.
        let source = """
            func main() { print(deeper(0)) }
            func deeper(_ n: Int) -> Int { deeper(n + 1) + 1 }
            """
        #expect(run(source, options: ["--debug"]).exitCode == Int32(bitPattern: 0xC000_00FD))
    }
    #endif

    @Test("build and run take a source whose path has spaces, and build writes the executable beside it")
    func pathWithSpaces() throws {
        try withTemporaryDirectory { directory in
            let folder = directory.appendingPathComponent("a folder", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try save("func main() { print(42) }", as: "the answer.rayo", in: folder)
            #expect(rayo(["run", "a folder/the answer.rayo"], in: directory) ==
                CommandResult(exitCode: 0, output: "42\n", errors: ""))

            #expect(rayo(["build", "a folder/the answer.rayo"], in: directory) ==
                CommandResult(exitCode: 0, output: "", errors: ""))
            #expect(try runExecutable(folder.appendingPathComponent(Executable.fileName("the answer"))) == "42\n")
        }
    }
}

struct IntegerTests {
    @Test("main prints the value of an integer expression")
    func printsArithmetic() {
        #expect(run("func main() { print(1 + 2 * 3) }") == CommandResult(exitCode: 0, output: "7\n", errors: ""))
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
                CommandResult(exitCode: 0, output: value + "\n", errors: ""))
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
                CommandResult(exitCode: 0, output: value + "\n", errors: ""))
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
            CommandResult(exitCode: 0, output: "-9141782528521893711\n", errors: ""))
    }

    @Test("a panic names the operation that fails, not the expression around it")
    func nestedPanic() {
        #expect(run("func main() { print(1 + (9223372036854775807 + 1)) }", options: ["--debug"]) == CommandResult(
            exitCode: ProgramRuntime.panicExitCode, output: "", errors: "main.rayo:1:25: panic: integer overflow\n"))
    }
}
