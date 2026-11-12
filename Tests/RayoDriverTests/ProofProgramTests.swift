import Foundation
import Testing
import RayoDriver

/// The repository's `examples` directory, three levels above this file.
private let examples = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("examples")

/// Each version's proof program: every `.rayo` file in a directory of `examples` named for a version, as `v0.1` is.
private func proofPrograms() throws -> [URL] {
    let directories = try FileManager.default.contentsOfDirectory(at: examples, includingPropertiesForKeys: nil)
    let versions = directories.filter { $0.lastPathComponent.wholeMatch(of: /v[0-9]+(\.[0-9]+)+/) != nil }
    return try versions.flatMap { version in
        try FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "rayo" }
    }
}

struct ProofProgramTests {
    @Test(arguments: try proofPrograms(), [["--debug"], ["--release"]])
    func `a version's proof program prints the output beside it, in debug and in release`(
        program: URL, mode: [String],
    ) throws {
        let expected = program.deletingPathExtension().appendingPathExtension("out")
        let output = try String(contentsOf: expected, encoding: .utf8)
        // `rayo(_:in:)` leaves the files that hold the output streams where it runs, so it runs apart from `examples`.
        let result = try withTemporaryDirectory { rayo(["run"] + mode + [program.path], in: $0) }
        #expect(result == CommandResult(exitCode: 0, output: output, errors: ""))
    }
}
