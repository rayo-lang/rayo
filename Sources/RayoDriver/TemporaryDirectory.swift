import Foundation

/// Temporary directories, for the files that `rayoc` needs only while one step of its work runs.
enum TemporaryDirectory {
    /// Runs `body` with a new, empty directory, and returns what `body` returns. The directory and everything in it
    /// are removed once `body` returns or throws.
    static func withNew<T>(_ body: (URL) throws -> T) throws -> T {
        // Name the directory so that no other run of `rayoc` picks it too.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayoc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // A directory that can't be removed is left behind, and doesn't fail the step that used it.
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}
