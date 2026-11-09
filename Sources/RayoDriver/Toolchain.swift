#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// The host tools that link object code into an executable and run it.
struct Toolchain {
    /// The environment that holds the search path for `clang`, and that a program runs in.
    var environment: [String: String]

    /// Links `objectCode` with the C library into an executable at `output`, with the `clang` on the search path.
    func link(_ objectCode: [UInt8], to output: URL) throws {
        let clang = try findClang()
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let object = directory.appendingPathComponent("program.o")
        try Data(objectCode).write(to: object)
        let result = try runCapturingOutput(clang, arguments: [object.path, "-o", output.path])
        if result.exitCode != 0 {
            throw Failure("clang failed:\n\(result.errors.hasSuffix("\n") ? String(result.errors.dropLast()) : result.errors)")
        }
    }

    /// Links `objectCode` into a temporary executable, runs it, and removes it.
    func linkAndRun(_ objectCode: [UInt8], output: Driver.ProgramOutput) throws -> Driver.Result {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("program")
        try link(objectCode, to: executable)
        switch output {
        case .captured: return try runCapturingOutput(executable)
        case .inherited: return Driver.Result(exitCode: try runAttached(executable), output: "", errors: "")
        }
    }

    private func findClang() throws(Failure) -> URL {
        let directories = environment["PATH", default: ""].split(separator: ":")
        for directory in directories {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("clang")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw Failure("can't find clang on the search path")
    }

    /// Runs `executable` to completion, and returns its exit code and what it wrote. Its output streams go
    /// to temporary files, so that neither can fill up and stall it while the other is read.
    private func runCapturingOutput(_ executable: URL, arguments: [String] = []) throws -> Driver.Result {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputFile = directory.appendingPathComponent("stdout")
        let errorFile = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)

        let process = newProcess(executable, arguments: arguments)
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
    private func runAttached(_ executable: URL) throws -> Int32 {
        // An interrupt from the terminal reaches the program and `rayoc` alike. `rayoc` outlives it, so that
        // it still removes the executable; a handled signal, unlike an ignored one, is reset in the program.
        let interrupt = signal(SIGINT) { _ in }
        let quit = signal(SIGQUIT) { _ in }
        defer {
            signal(SIGINT, interrupt)
            signal(SIGQUIT, quit)
        }
        return try runToCompletion(newProcess(executable))
    }

    private func newProcess(_ executable: URL, arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        return process
    }

    /// The exit code of `process`, or 128 plus the signal that ended it.
    private func runToCompletion(_ process: Process) throws -> Int32 {
        try process.run()
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }

    /// Creates a new, empty directory, which the caller removes.
    private static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayoc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
