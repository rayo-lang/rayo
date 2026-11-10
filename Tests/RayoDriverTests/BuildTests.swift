import Foundation
import Testing
import RayoDriver

/// A new, empty directory, which `body` may fill and which is removed after it.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
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
            // Build the source in the directory.
            let source = directory.appendingPathComponent("answer.rayo").path
            let result = Driver.run(["build", source]) { $0 == source ? Array("func main() { print(42) }".utf8) : nil }
            #expect(result == Driver.Result(exitCode: 0, output: "", errors: ""))

            // Run the executable it wrote.
            let output = try runExecutable(directory.appendingPathComponent("answer"))
            #expect(output == "42\n")
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
            // Make a directory named clang.
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
            let failing = "echo 'clang: something broke' >&2\nexit 1"
            let clang = try script(failing, at: directory.appendingPathComponent("clang"))
            let tools = Driver.LinkTools(clang: clang, lld: Driver.LinkTools.installed.lld)
            #expect(runEmptyMain(linkTools: tools) ==
                Driver.Result(exitCode: 1, output: "", errors: "rayoc: clang failed:\nclang: something broke\n"))
        }
    }

    @Test("rayoc compiles the program itself, and clang only links it")
    func clangOnlyLinks() throws {
        try withTemporaryDirectory { directory in
            // Make a clang that hands what it is given to the installed clang, unless it is source to compile.
            let clang = try script("""
                for argument in "$@"; do
                    case "$argument" in
                        *.ll|*.bc|*.c|*.s) echo "clang: asked to compile $argument" >&2; exit 1 ;;
                    esac
                done
                exec '\(Driver.LinkTools.installed.clang.path)' "$@"
                """, at: directory.appendingPathComponent("clang"))
            let tools = Driver.LinkTools(clang: clang, lld: Driver.LinkTools.installed.lld)

            let result = Driver.run(["run", "main.rayo"], linkTools: tools) { _ in
                Array("func main() { print(42) }".utf8)
            }
            #expect(result == Driver.Result(exitCode: 0, output: "42\n", errors: ""))
        }
    }

    @Test("each linker links an executable that runs, and LLD links unless the platform's linker is asked for",
          arguments: [(["--linker=lld"], true), (["--linker=platform"], false), ([], true)])
    func linkers(options: [String], linksWithLLD: Bool) throws {
        try withTemporaryDirectory { directory in
            // Make an LLD that records it ran, and hands what it is given to the installed LLD.
            let installed = Driver.LinkTools.installed
            let ran = directory.appendingPathComponent("lld-ran")
            let lld = try script("touch '\(ran.path)'\nexec '\(installed.lld.path)' \"$@\"",
                                 at: directory.appendingPathComponent(installed.lld.lastPathComponent))

            // Build with that LLD, and with the linker that `options` name.
            let source = directory.appendingPathComponent("answer.rayo").path
            let tools = Driver.LinkTools(clang: installed.clang, lld: lld)
            let result = Driver.run(["build"] + options + [source], linkTools: tools) {
                $0 == source ? Array("func main() { print(42) }".utf8) : nil
            }

            // The executable runs, whichever linker linked it, and the LLD ran only where it is the linker.
            #expect(result == Driver.Result(exitCode: 0, output: "", errors: ""))
            #expect(try runExecutable(directory.appendingPathComponent("answer")) == "42\n")
            #expect(FileManager.default.fileExists(atPath: ran.path) == linksWithLLD)
        }
    }

    @Test("linking with LLD needs the LLD of the LLVM install, and the platform's linker doesn't")
    func lldMissing() throws {
        let lld = URL(fileURLWithPath: "/nonexistent/ld.lld")
        let tools = Driver.LinkTools(clang: Driver.LinkTools.installed.clang, lld: lld)

        // A link with LLD fails, and says how to get it or do without it.
        #expect(runEmptyMain(linkTools: tools) == Driver.Result(exitCode: 1, output: "", errors: """
            rayoc: can't find LLD at '/nonexistent/ld.lld': install LLD 23, run 'swift package purge-cache' and \
            build rayoc again, or link with --linker=platform

            """))

        // A link with the platform's linker needs no LLD.
        #expect(runEmptyMain(options: ["--linker=platform"], linkTools: tools) ==
            Driver.Result(exitCode: 0, output: "", errors: ""))
    }

    @Test("the platform's linker is the platform's, not an ld first on the search path")
    func platformLinkerIgnoresSearchPath() throws {
        try withTemporaryDirectory { directory in
            // Make an `ld` that records it ran and fails.
            let ran = directory.appendingPathComponent("ld-ran")
            _ = try script("touch '\(ran.path)'\nexit 1", at: directory.appendingPathComponent("ld"))

            // Run with that `ld` first on the search path.
            let path = ProcessInfo.processInfo.environment["PATH", default: ""]
            let result = Driver.run(["run", "--linker=platform", "main.rayo"],
                                    environment: ["PATH": "\(directory.path):\(path)"]) { _ in
                Array("func main() { print(42) }".utf8)
            }

            // The program ran, linked by a linker other than that `ld`.
            #expect(result == Driver.Result(exitCode: 0, output: "42\n", errors: ""))
            #expect(!FileManager.default.fileExists(atPath: ran.path))
        }
    }

    @Test("an executable exports the C entry point and nothing of the program or the runtime")
    func exportedSymbols() throws {
        try withTemporaryDirectory { directory in
            // Build an empty program.
            let source = directory.appendingPathComponent("empty.rayo").path
            #expect(Driver.run(["build", source]) { _ in Array("func main() {}".utf8) } ==
                Driver.Result(exitCode: 0, output: "", errors: ""))

            // List the symbols the executable defines and exports.
            let nm = Process()
            nm.executableURL = Driver.LinkTools.installed.clang.deletingLastPathComponent()
                .appendingPathComponent("llvm-nm")
            nm.arguments = ["--extern-only", "--defined-only", directory.appendingPathComponent("empty").path]
            let listing = Pipe()
            nm.standardOutput = listing
            try nm.run()
            let lines = String(decoding: listing.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n")
            nm.waitUntilExit()

            // Each line ends in a symbol's name, which is `main` for the C entry point, `_main` on Mach-O.
            let symbols = lines.compactMap { $0.split(separator: " ").last.map(String.init) }
            #expect(symbols.contains { $0 == "main" || $0 == "_main" })
            #expect(symbols.filter { $0.contains("rayo.") } == [])
        }
    }

    @Test("build builds in the mode it names")
    func buildMode() throws {
        try withTemporaryDirectory { directory in
            // Build a program that overflows, in a debug build.
            let source = directory.appendingPathComponent("overflow.rayo").path
            let program = "func main() { print(9223372036854775807 + 1) }"
            #expect(Driver.run(["build", "--debug", source]) { _ in Array(program.utf8) } ==
                Driver.Result(exitCode: 0, output: "", errors: ""))

            // Run the executable, and read what it reports.
            let executable = Process()
            executable.executableURL = directory.appendingPathComponent("overflow")
            let errors = Pipe()
            executable.standardError = errors
            try executable.run()
            executable.waitUntilExit()
            let reported = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

            // The overflow panics, as it does in a debug build.
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
