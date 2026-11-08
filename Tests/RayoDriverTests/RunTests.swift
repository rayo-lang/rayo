import Foundation
import Testing
import RayoDriver

/// Compiles `source` as `main.rayo` in the build mode `options` name, and runs it.
func run(_ source: String, options: [String] = []) -> Driver.Result {
    Driver.run(["run"] + options + ["main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
}

/// What a run that panics reports: the panic on the error stream, after the output so far.
func panicked(_ message: String, output: String = "") -> Driver.Result {
    Driver.Result(exitCode: Driver.panicExitCode, output: output, errors: "main.rayo:\(message)\n")
}

/// A new, empty directory, which `body` may fill and which is removed after it.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
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

    @Test("build and run need clang on the search path")
    func clangMissing() {
        let result = Driver.run(["run", "main.rayo"], environment: ["PATH": "/nonexistent"]) { _ in
            Array("func main() {}".utf8)
        }
        #expect(result == Driver.Result(exitCode: 1, output: "", errors: "rayoc: can't find clang on the search path\n"))
    }

    @Test("a clang that fails has its errors reported")
    func clangFails() throws {
        try withTemporaryDirectory { directory in
            let clang = directory.appendingPathComponent("clang")
            try Data("#!/bin/sh\necho 'clang: something broke' >&2\nexit 1\n".utf8).write(to: clang)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: clang.path)
            let result = Driver.run(["run", "main.rayo"], environment: ["PATH": directory.path]) { _ in
                Array("func main() {}".utf8)
            }
            #expect(result == Driver.Result(exitCode: 1, output: "", errors: "rayoc: clang failed:\nclang: something broke\n"))
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
            #expect(run("func main() { print(\(expression)) }", options: mode) ==
                panicked("1:21: panic: \(operation) by zero"))
        }
    }

    @Test("in a debug build, overflow panics at the operation, after the output so far", arguments: [
        "9223372036854775807 + 1",
        "-9223372036854775807 - 2",
        "4611686018427387904 * 2",
        "-9223372036854775808 / -1",
        "-(-9223372036854775807 - 1)",
    ])
    func overflowPanics(expression: String) {
        #expect(run("func main() {\n    print(1)\n    print(\(expression))\n}", options: ["--debug"]) ==
            panicked("3:11: panic: integer overflow", output: "1\n"))
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

    @Test("a panic names the operation that fails, not the expression around it")
    func nestedPanic() {
        #expect(run("func main() { print(1 + (9223372036854775807 + 1)) }", options: ["--debug"]) ==
            panicked("1:25: panic: integer overflow"))
    }
}
