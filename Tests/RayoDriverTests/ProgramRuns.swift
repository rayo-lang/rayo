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
    // A run that exits otherwise, or writes no line about `path`, didn't panic there.
    guard result.exitCode == Driver.panicExitCode, result.errors.hasPrefix(path + ":"), result.errors.hasSuffix("\n")
    else { return nil }

    // Split the line after the path into its line, column, `panic` and reason.
    let line = result.errors.dropFirst(path.count + 1).dropLast()
    let fields = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)

    // Anything but one line of a position, ` panic` and a reason is no panic's report.
    guard !line.contains("\n"), fields.count == 4, fields[0..<2].allSatisfy(isNumeral), fields[2] == " panic",
          fields[3].hasPrefix(" ") else { return nil }

    return Panic(reason: String(fields[3].dropFirst()), output: result.output)
}

/// Whether `text` is one or more decimal digits.
private func isNumeral(_ text: Substring) -> Bool {
    !text.isEmpty && text.allSatisfy { ("0"..."9").contains($0) }
}
