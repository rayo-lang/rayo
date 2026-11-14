import Foundation
import Testing

/// A file kept in the repo, in the `Snapshots` directory beside a test file, that holds the text a test expects.
///
/// A test compares the text it gets with the file's, and records a diff where they differ. With
/// `RAYO_UPDATE_SNAPSHOTS=1` in the environment it writes the text to the file instead, so a change that means to
/// change the text updates the file.
public struct Snapshot {
    private let file: URL

    /// The snapshot `name`, such as `if-else.ir`, beside the test file at `testFile`.
    public init(_ name: String, besideTestFile testFile: StaticString = #filePath) {
        let testDirectory = URL(fileURLWithPath: "\(testFile)").deletingLastPathComponent()
        file = testDirectory.appendingPathComponent("Snapshots").appendingPathComponent(name)
    }

    /// Records an issue at `sourceLocation` where `text` isn't the snapshot's, or writes it to the snapshot where the
    /// environment asks for snapshots to be updated.
    public func expect(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        // Updating writes the text, whatever the file held.
        if ProcessInfo.processInfo.environment["RAYO_UPDATE_SNAPSHOTS"] == "1" {
            write(text, sourceLocation: sourceLocation)
            return
        }

        // A missing snapshot shows the text it would hold.
        guard let expected = try? String(contentsOf: file, encoding: .utf8) else {
            let comment = "no snapshot at \(file.path); RAYO_UPDATE_SNAPSHOTS=1 writes it as:\n\(text)"
            Issue.record(Comment(rawValue: comment), sourceLocation: sourceLocation)
            return
        }

        // A snapshot that differs shows how.
        if expected != text {
            let diff = LineDiff(from: expected, to: text)
            let comment = "\(file.path) differs (- snapshot, + actual):\n\(diff)"
            Issue.record(Comment(rawValue: comment), sourceLocation: sourceLocation)
        }
    }

    /// Writes `text` to the snapshot's file, and records an issue at `sourceLocation` where it can't.
    private func write(_ text: String, sourceLocation: SourceLocation) {
        do {
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            Issue.record(error, "can't write \(file.path)", sourceLocation: sourceLocation)
        }
    }
}
