import Foundation

/// A new, empty directory, which `body` may fill and which is removed after it.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

/// Saves `source` as the file `name` in `directory`, and returns the file's path.
func save(_ source: String, as name: String, in directory: URL) throws -> String {
    let file = directory.appendingPathComponent(name)
    try Data(source.utf8).write(to: file)
    return file.path
}

/// Writes a shell script running `body` to `url`, makes it executable, and returns `url`.
func script(_ body: String, at url: URL) throws -> URL {
    try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
