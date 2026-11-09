import Foundation
import Testing
import RayoDriver

/// Compiles `source` as `main.rayo` in the build mode `options` name, and runs it.
func run(_ source: String, options: [String] = []) -> Driver.Result {
    Driver.run(["run"] + options + ["main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
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
func panic(in result: Driver.Result, file path: String = "main.rayo") -> Panic? {
    guard result.exitCode == Driver.panicExitCode, result.errors.hasPrefix(path + ":"), result.errors.hasSuffix("\n")
    else { return nil }
    let line = result.errors.dropFirst(path.count + 1).dropLast()
    let fields = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
    guard !line.contains("\n"), fields.count == 4, fields[0..<2].allSatisfy(isNumeral), fields[2] == " panic",
          fields[3].hasPrefix(" ") else { return nil }
    return Panic(reason: String(fields[3].dropFirst()), output: result.output)
}

private func isNumeral(_ text: Substring) -> Bool {
    !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
}

/// A new, empty directory, which `body` may fill and which is removed after it.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// Runs an empty `main`, linked with `linkTools` in the way `options` name.
private func runEmptyMain(options: [String] = [], linkTools: Driver.LinkTools) -> Driver.Result {
    Driver.run(["run"] + options + ["main.rayo"], linkTools: linkTools) { _ in Array("func main() {}".utf8) }
}

/// Writes a shell script running `body` to `url`, makes it executable, and returns `url`.
private func script(_ body: String, at url: URL) throws -> URL {
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// What `executable` writes to its standard output, once it exits with 0.
private func runExecutable(_ executable: URL) throws -> String {
    let process = Process()
    process.executableURL = executable
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let written = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return written
}

struct BuildTests {
    @Test("build writes an executable beside the source, named after it")
    func build() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("answer.rayo").path
            let result = Driver.run(["build", source]) { $0 == source ? Array("func main() { print(42) }".utf8) : nil }
            #expect(result == Driver.Result(exitCode: 0, output: "", errors: ""))

            let program = Process()
            program.executableURL = directory.appendingPathComponent("answer")
            let output = Pipe()
            program.standardOutput = output
            try program.run()
            program.waitUntilExit()
            #expect(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "42\n")
            #expect(program.terminationStatus == 0)
        }
    }

    @Test("build needs a name before '.rayo', so the executable can't replace the source", arguments: [
        ("answer", "'answer' doesn't end in '.rayo'"),
        ("dir/.rayo", "'dir/.rayo' has no name before '.rayo'"),
        ("dir/..rayo", "'dir/..rayo' has no name before '.rayo'"),
        ("dir/...rayo", "'dir/...rayo' has no name before '.rayo'"),
    ])
    func nameRequired(path: String, message: String) {
        // The file can't be read, so a check that lets the path through fails without writing anything.
        #expect(Driver.run(["build", path]) { _ in nil } ==
            Driver.Result(exitCode: 1, output: "", errors: "rayoc: \(message)\n"))
    }

    @Test("build and run need the clang of the LLVM install, and a directory named clang isn't one")
    func clangMissing() throws {
        try withTemporaryDirectory { directory in
            let decoy = directory.appendingPathComponent("clang")
            try FileManager.default.createDirectory(at: decoy, withIntermediateDirectories: true)
            for clang in [directory.appendingPathComponent("nonexistent"), decoy] {
                let tools = Driver.LinkTools(clang: clang, lld: Driver.LinkTools.installed.lld)
                #expect(runEmptyMain(linkTools: tools) ==
                    Driver.Result(exitCode: 1, output: "", errors: "rayoc: can't find clang at '\(clang.path)'\n"))
            }
        }
    }

    @Test("a clang that fails has its errors reported")
    func clangFails() throws {
        try withTemporaryDirectory { directory in
            let clang = try script("echo 'clang: something broke' >&2\nexit 1", at: directory.appendingPathComponent("clang"))
            let tools = Driver.LinkTools(clang: clang, lld: Driver.LinkTools.installed.lld)
            #expect(runEmptyMain(linkTools: tools) ==
                Driver.Result(exitCode: 1, output: "", errors: "rayoc: clang failed:\nclang: something broke\n"))
        }
    }

    @Test("rayoc compiles the program itself, and clang only links it")
    func clangOnlyLinks() throws {
        try withTemporaryDirectory { directory in
            // Hands what it is given to the installed clang, unless it is source clang would compile.
            let clang = try script("""
                for argument in "$@"; do
                    case "$argument" in
                        *.ll|*.bc|*.c|*.s) echo "clang: asked to compile $argument" >&2; exit 1 ;;
                    esac
                done
                exec '\(Driver.LinkTools.installed.clang.path)' "$@"
                """, at: directory.appendingPathComponent("clang"))
            let tools = Driver.LinkTools(clang: clang, lld: Driver.LinkTools.installed.lld)
            let result = Driver.run(["run", "main.rayo"], linkTools: tools) { _ in Array("func main() { print(42) }".utf8) }
            #expect(result == Driver.Result(exitCode: 0, output: "42\n", errors: ""))
        }
    }

    @Test("each linker links an executable that runs, and LLD links unless the platform's linker is asked for",
          arguments: [(["--linker=lld"], true), (["--linker=platform"], false), ([], true)])
    func linkers(options: [String], linksWithLLD: Bool) throws {
        try withTemporaryDirectory { directory in
            // Records that it ran, and hands what it is given to the installed LLD.
            let ran = directory.appendingPathComponent("lld-ran")
            let lld = try script("touch '\(ran.path)'\nexec '\(Driver.LinkTools.installed.lld.path)' \"$@\"",
                                 at: directory.appendingPathComponent(Driver.LinkTools.installed.lld.lastPathComponent))
            let source = directory.appendingPathComponent("answer.rayo").path
            let result = Driver.run(["build"] + options + [source], linkTools: Driver.LinkTools(clang: Driver.LinkTools.installed.clang, lld: lld)) {
                $0 == source ? Array("func main() { print(42) }".utf8) : nil
            }
            #expect(result == Driver.Result(exitCode: 0, output: "", errors: ""))
            #expect(try runExecutable(directory.appendingPathComponent("answer")) == "42\n")
            #expect(FileManager.default.fileExists(atPath: ran.path) == linksWithLLD)
        }
    }

    @Test("linking with LLD needs the LLD of the LLVM install, and the platform's linker doesn't")
    func lldMissing() throws {
        let lld = URL(fileURLWithPath: "/nonexistent/ld.lld")
        let tools = Driver.LinkTools(clang: Driver.LinkTools.installed.clang, lld: lld)
        #expect(runEmptyMain(linkTools: tools) == Driver.Result(exitCode: 1, output: "", errors: """
            rayoc: can't find LLD at '/nonexistent/ld.lld': install LLD 23, run 'swift package purge-cache' and \
            build rayoc again, or link with --linker=platform

            """))
        #expect(runEmptyMain(options: ["--linker=platform"], linkTools: tools) ==
            Driver.Result(exitCode: 0, output: "", errors: ""))
    }

    @Test("the platform's linker is the platform's, not an ld first on the search path")
    func platformLinkerIgnoresSearchPath() throws {
        try withTemporaryDirectory { directory in
            let ran = directory.appendingPathComponent("ld-ran")
            _ = try script("touch '\(ran.path)'\nexit 1", at: directory.appendingPathComponent("ld"))
            let path = ProcessInfo.processInfo.environment["PATH", default: ""]
            let result = Driver.run(["run", "--linker=platform", "main.rayo"],
                                    environment: ["PATH": "\(directory.path):\(path)"]) { _ in
                Array("func main() { print(42) }".utf8)
            }
            #expect(result == Driver.Result(exitCode: 0, output: "42\n", errors: ""))
            #expect(!FileManager.default.fileExists(atPath: ran.path))
        }
    }

    @Test("an executable exports the C entry point and nothing of the program or the runtime")
    func exportedSymbols() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("empty.rayo").path
            #expect(Driver.run(["build", source]) { _ in Array("func main() {}".utf8) } ==
                Driver.Result(exitCode: 0, output: "", errors: ""))

            let nm = Process()
            nm.executableURL = Driver.LinkTools.installed.clang.deletingLastPathComponent()
                .appendingPathComponent("llvm-nm")
            nm.arguments = ["--extern-only", "--defined-only", directory.appendingPathComponent("empty").path]
            let listing = Pipe()
            nm.standardOutput = listing
            try nm.run()
            let symbols = String(decoding: listing.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) }
            nm.waitUntilExit()
            #expect(symbols.contains { $0 == "main" || $0 == "_main" })
            #expect(symbols.filter { $0.contains("rayo.") } == [])
        }
    }

    @Test("build builds in the mode it names")
    func buildMode() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("overflow.rayo").path
            let program = "func main() { print(9223372036854775807 + 1) }"
            #expect(Driver.run(["build", "--debug", source]) { _ in Array(program.utf8) } ==
                Driver.Result(exitCode: 0, output: "", errors: ""))

            let executable = Process()
            executable.executableURL = directory.appendingPathComponent("overflow")
            let errors = Pipe()
            executable.standardError = errors
            try executable.run()
            executable.waitUntilExit()
            let reported = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let result = Driver.Result(exitCode: executable.terminationStatus, output: "", errors: reported)
            #expect(panic(in: result, file: source) == Panic(reason: "integer overflow"))
        }
    }

    @Test("a run whose output is the terminal's ends with the program's exit status")
    func attached() {
        let result = Driver.run(["run", "main.rayo"], programOutput: .inherited) { _ in
            Array("func main() { print(1 / 0) }".utf8)
        }
        #expect(result == Driver.Result(exitCode: Driver.panicExitCode, output: "", errors: ""))
    }
}

struct IntegerTests {
    @Test("main prints the value of an integer expression")
    func printsArithmetic() {
        #expect(run("func main() { print(1 + 2 * 3) }") == Driver.Result(exitCode: 0, output: "7\n", errors: ""))
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
                Driver.Result(exitCode: 0, output: value + "\n", errors: ""))
        }
    }

    @Test("division and remainder by zero panic in every build", arguments: [("1 / 0", "division"), ("1 % 0", "remainder")])
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
                Driver.Result(exitCode: 0, output: value + "\n", errors: ""))
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
            Driver.Result(exitCode: 0, output: "-9141782528521893711\n", errors: ""))
    }

    @Test("a panic names the operation that fails, not the expression around it")
    func nestedPanic() {
        #expect(run("func main() { print(1 + (9223372036854775807 + 1)) }", options: ["--debug"]) == Driver.Result(
            exitCode: Driver.panicExitCode, output: "", errors: "main.rayo:1:25: panic: integer overflow\n"))
    }
}
