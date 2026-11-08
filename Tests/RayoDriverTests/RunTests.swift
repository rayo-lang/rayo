import Foundation
import Testing
import RayoDriver

/// Compiles `source` as `main.rayo` and runs it.
func run(_ source: String) -> Driver.Result {
    Driver.run(["run", "main.rayo"]) { $0 == "main.rayo" ? source : nil }
}

/// What a run that panics reports: the panic on the error stream, after the output so far.
func panicked(_ message: String, output: String = "") -> Driver.Result {
    Driver.Result(exitCode: Driver.panicExitCode, output: output, errors: "main.rayo:\(message)\n")
}

struct BuildTests {
    @Test("build writes an executable beside the source, named after it")
    func build() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("answer.rayo").path
        let result = Driver.run(["build", source]) { $0 == source ? "func main() { print(42) }" : nil }
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

    @Test("build needs a name before '.rayo', so the executable can't replace the source", arguments: [
        ("answer", "'answer' doesn't end in '.rayo'"),
        ("dir/.rayo", "'dir/.rayo' has no name before '.rayo'"),
    ])
    func nameRequired(path: String, message: String) {
        #expect(Driver.run(["build", path]) { _ in "func main() {}" } ==
            Driver.Result(exitCode: 1, output: "", errors: "rayoc: \(message)\n"))
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
    ])
    func division(expression: String, value: String) {
        #expect(run("func main() { print(\(expression)) }") == Driver.Result(exitCode: 0, output: value + "\n", errors: ""))
    }

    @Test("division and remainder by zero panic", arguments: [("1 / 0", "division"), ("1 % 0", "remainder")])
    func byZero(expression: String, operation: String) {
        #expect(run("func main() { print(\(expression)) }") == panicked("1:21: panic: \(operation) by zero"))
    }

    @Test("overflow panics at the operation, after the output so far", arguments: [
        "9223372036854775807 + 1",
        "-9223372036854775807 - 2",
        "4611686018427387904 * 2",
        "-9223372036854775808 / -1",
        "-(-9223372036854775807 - 1)",
    ])
    func overflowPanics(expression: String) {
        #expect(run("func main() {\n    print(1)\n    print(\(expression))\n}") ==
            panicked("3:11: panic: integer overflow", output: "1\n"))
    }

    @Test("a panic names the operation that fails, not the expression around it")
    func nestedPanic() {
        #expect(run("func main() { print(1 + (9223372036854775807 + 1)) }") == panicked("1:25: panic: integer overflow"))
    }
}
