import Foundation
import Testing
import RayoDriver

/// The repository's `examples` directory, which holds each version's proof program beside its expected output.
private let examples = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("examples")

struct ProofProgramTests {
    @Test(arguments: ["v0.1/combat"], [["--debug"], ["--release"]])
    func `a version's proof program prints its expected output, in debug and in release`(
        program: String, mode: [String],
    ) throws {
        let source = examples.appendingPathComponent(program + ".rayo")
        let expected = try String(contentsOf: examples.appendingPathComponent(program + ".out"), encoding: .utf8)
        // `rayo(_:in:)` leaves the files that hold the output streams where it runs, so it runs apart from `examples`.
        let result = try withTemporaryDirectory { rayo(["run"] + mode + [source.path], in: $0) }
        #expect(result == CommandResult(exitCode: 0, output: expected, errors: ""))
    }
}
