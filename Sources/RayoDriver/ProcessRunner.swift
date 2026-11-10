#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// Runs host executables, such as clang and a linked program, in one environment.
struct ProcessRunner {
    /// The environment the executables run in.
    var environment: [String: String]

    /// Runs `executable` with `arguments` and nothing on its standard input until it exits, and returns its exit code
    /// and what it wrote to its standard output and error.
    func runCapturingOutput(_ executable: URL, arguments: [String] = []) throws -> ProcessResult {
        try TemporaryDirectory.withNew { directory in
            // Give each output stream a file, so neither can fill up and stall the executable while the other is read.
            let outputFile = directory.appendingPathComponent("stdout")
            let errorFile = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: outputFile.path, contents: nil)
            FileManager.default.createFile(atPath: errorFile.path, contents: nil)

            // Run the executable with nothing to read, writing to those files.
            let process = newProcess(executable, arguments: arguments)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = try FileHandle(forWritingTo: outputFile)
            process.standardError = try FileHandle(forWritingTo: errorFile)
            let exitCode = try Self.runToCompletion(process)

            return ProcessResult(exitCode: exitCode,
                                 output: try String(contentsOf: outputFile, encoding: .utf8),
                                 errors: try String(contentsOf: errorFile, encoding: .utf8))
        }
    }

    /// Runs `executable` to completion on `rayoc`'s own standard input, output and error, and returns its exit code.
    /// An interrupt or quit from the terminal reaches the executable, and leaves `rayoc` running.
    func runAttached(_ executable: URL) throws -> Int32 {
        try Self.survivingTerminalSignals {
            try Self.runToCompletion(newProcess(executable))
        }
    }

    /// A process that runs `executable` with `arguments` in the environment.
    private func newProcess(_ executable: URL, arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        return process
    }

    /// Runs `process` to its end, and returns its exit code, or 128 plus the number of the signal that ended it.
    private static func runToCompletion(_ process: Process) throws -> Int32 {
        // Start the process, and wait for it to end.
        try process.run()
        process.waitUntilExit()

        // A process that a signal ended reports 128 plus the signal, as a shell does.
        if process.terminationReason == .uncaughtSignal { return 128 + process.terminationStatus }
        // A process that exited reports its own exit code.
        return process.terminationStatus
    }

    /// Runs `body`, and returns what it returns, while an interrupt or quit from the terminal leaves `rayoc` running.
    private static func survivingTerminalSignals<T>(_ body: () throws -> T) rethrows -> T {
        // Catch both with a no-op handler; a program started meanwhile resets a caught signal, not an ignored one.
        let interrupt = signal(SIGINT) { _ in }
        let quit = signal(SIGQUIT) { _ in }
        defer {
            signal(SIGINT, interrupt)
            signal(SIGQUIT, quit)
        }

        return try body()
    }
}
