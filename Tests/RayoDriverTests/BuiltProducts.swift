import Foundation
import Testing
import RayoDriver

/// Marks the bundle these tests build into, so that its place on disk can be found.
private final class TestBundle {}

/// The executable `name` that the package's build puts beside these tests: `rayo`, `rayoc` or `tool-stand-in`.
func builtProduct(_ name: String) -> URL {
    let bundle = Bundle(for: TestBundle.self).bundleURL
    // On macOS the tests are an `.xctest` bundle beside the products; elsewhere they are an executable among them.
    let products = bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : bundle
    return products.appendingPathComponent(name)
}

/// Runs the built `rayo` with `arguments` in `directory`, as a user would there, and gives what it exits with and
/// what it writes. A run that can't start is recorded as an issue, and gives exit code -1.
func rayo(_ arguments: [String], in directory: URL) -> CommandResult {
    do {
        // Give each output stream a file, so that neither fills up and stalls the run while the other is read.
        let outputFile = directory.appendingPathComponent(".rayo-stdout")
        let errorFile = directory.appendingPathComponent(".rayo-stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)

        // Run `rayo` there, and give what it wrote.
        let process = Process()
        process.executableURL = builtProduct("rayo")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = try FileHandle(forWritingTo: outputFile)
        process.standardError = try FileHandle(forWritingTo: errorFile)
        try process.run()
        process.waitUntilExit()
        return CommandResult(exitCode: process.terminationStatus,
                             output: try String(contentsOf: outputFile, encoding: .utf8),
                             errors: try String(contentsOf: errorFile, encoding: .utf8))
    } catch {
        Issue.record(error)
        return CommandResult(exitCode: -1, output: "", errors: "")
    }
}
