import Foundation

/// The host tools that turn LLVM IR into an executable and run it.
enum Toolchain {
    struct Failure: Error {
        var message: String
    }

    /// Compiles and links `llvmIR` into an executable at `output`, with the `clang` on the search path.
    static func link(_ llvmIR: String, to output: URL) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let module = directory.appendingPathComponent("module.ll")
        try Data(llvmIR.utf8).write(to: module)
        // The module leaves the target to clang, which would otherwise warn that it chose one.
        let result = try runCapturingOutput(URL(fileURLWithPath: "/usr/bin/env"),
                                            arguments: ["clang", "-Wno-override-module", module.path, "-o", output.path])
        if result.exitCode != 0 { throw Failure(message: "clang failed:\n\(result.errors)") }
    }

    /// Runs `executable` to completion, and returns its exit code and what it wrote. Its output streams go
    /// to temporary files, so that neither can fill up and stall it while the other is read.
    static func runCapturingOutput(_ executable: URL, arguments: [String] = []) throws -> Driver.Result {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputFile = directory.appendingPathComponent("stdout")
        let errorFile = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = try FileHandle(forWritingTo: outputFile)
        process.standardError = try FileHandle(forWritingTo: errorFile)
        let exitCode = try runToCompletion(process)
        return Driver.Result(exitCode: exitCode,
                             output: try String(contentsOf: outputFile, encoding: .utf8),
                             errors: try String(contentsOf: errorFile, encoding: .utf8))
    }

    /// Runs `executable` to completion on `rayoc`'s own standard input, output and error, and returns its
    /// exit code.
    static func runAttached(_ executable: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        return try runToCompletion(process)
    }

    /// The exit code of `process`, or 128 plus the signal that ended it.
    private static func runToCompletion(_ process: Process) throws -> Int32 {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }

    /// Creates a new, empty directory, which the caller removes.
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayoc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
