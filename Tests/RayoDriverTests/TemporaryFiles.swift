import Foundation

/// A new, empty directory, which `body` may fill and which is removed after it.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// A new, empty directory, which `body` may fill as it awaits, and which is removed after it.
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    return try await body(directory)
}

/// Makes a new, empty directory, under a name no other test takes, and returns it.
private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// Saves `source` as the file `name` in `directory`, and returns the file's path.
func save(_ source: String, as name: String, in directory: URL) throws -> String {
    let file = directory.appendingPathComponent(name)
    try Data(source.utf8).write(to: file)
    return file.path
}
