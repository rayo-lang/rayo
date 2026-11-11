#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(CRT)
import CRT
#endif
import Foundation
import RayoLLVMInstall

/// The host tools that compile a source file, link its object code into an executable, and run it.
struct Toolchain {
    /// The `rayoc` that compiles.
    var compiler: URL
    var tools: LinkTools
    var linker: Linker
    /// Where what `rayoc` and a program write goes.
    var output: ProcessOutput
    /// The environment that `rayoc`, clang and a program run in.
    var environment: [String: String]

    /// Has `rayoc` check the source file at `path`, and returns what `rayoc` wrote to its standard error, where
    /// `output` captures it.
    func check(_ path: String) throws(CommandError) -> String {
        try runCompiler(["--check", "--", path])
    }

    /// Has `rayoc` compile the source file at `path` to object code in `mode`, and runs `body` on the object file,
    /// which is removed once `body` ends. Returns what `body` returns, and what `rayoc` wrote to its standard error,
    /// where `output` captures it.
    func compile<Value>(
        _ path: String, mode: BuildMode, _ body: (URL) throws(CommandError) -> Value,
    ) throws(CommandError) -> (value: Value, errors: String) {
        try Self.withTemporaryDirectory { directory throws(CommandError) in
            // Have `rayoc` write the object file inside the directory, so it goes with the directory.
            let objectFile = directory.appendingPathComponent("program.o")
            let errors = try runCompiler([mode.rawValue, "-o", objectFile.path, "--", path])

            // Run the body on the object file; what `rayoc` wrote comes before why the body stopped, if it did.
            do throws(CommandError) {
                return (try body(objectFile), errors)
            } catch {
                // A body that stops does so after what `rayoc` wrote.
                throw error.after(errors)
            }
        }
    }

    /// Links the object file at `objectFile` with the C library into an executable at `executable`.
    func link(_ objectFile: URL, to executable: URL) throws(CommandError) {
        // A link needs clang, which drives it, so a missing clang stops it; then the arguments that have clang run
        // the linker asked for.
        guard Self.isExecutableFile(tools.clang) else {
            throw .failed("can't find clang at '\(tools.clang.path)'")
        }
        let linkerArguments = try linkerArguments()

        // Have clang link the object file into the executable.
        let arguments = linkerArguments + [objectFile.path, "-o", executable.path]
        let run = try runCapturingOutput(tools.clang, arguments: arguments)
        // A link that clang fails reports what clang wrote, without its last newline.
        if run.termination.exitCode != 0 {
            let errors = run.errors.hasSuffix("\n") ? String(run.errors.dropLast()) : run.errors
            throw .failed("clang failed:\n\(errors)")
        }
    }

    /// Links the object file at `objectFile` into a temporary executable, runs it, and removes it.
    func linkAndRun(_ objectFile: URL) throws(CommandError) -> CommandResult {
        try Self.withTemporaryDirectory { directory throws(CommandError) in
            // Link the executable inside the directory, so it goes with the directory once the run ends.
            let executable = directory.appendingPathComponent("program")
            try link(objectFile, to: executable)

            // Run it, and give how it ended and what of its output was captured.
            let run = try runSendingOutput(executable)
            return CommandResult(exitCode: run.termination.exitCode, output: run.output, errors: run.errors)
        }
    }

    /// Runs `rayoc` with `arguments`, and returns what it wrote to its standard error, where `output` captures it,
    /// or fails as `rayoc` ended when it doesn't compile the file.
    private func runCompiler(_ arguments: [String]) throws(CommandError) -> String {
        // Without `rayoc` there is nothing to compile with.
        guard Self.isExecutableFile(compiler) else { throw .failed("can't find rayoc at '\(compiler.path)'") }

        // Run `rayoc`, and go on or stop as it ended.
        let run = try runSendingOutput(compiler, arguments: arguments)
        switch run.termination {
        // A `rayoc` that compiled the file leaves the command to go on.
        case .exited(0):
            return run.errors
        // A file that `rayoc` doesn't compile ends the command as `rayoc` ended.
        case .exited(let exitCode):
            throw .compileFailed(exitCode: exitCode, errors: run.errors)
        // A `rayoc` that a signal ended couldn't say so, so `rayo` does.
        case .signaled(let signal):
            throw .compileFailed(exitCode: run.termination.exitCode,
                                 errors: run.errors + "rayo: rayoc was ended by signal \(signal)\n")
        }
    }

    /// Finds `linker`, and returns the arguments that have clang link with it.
    private func linkerArguments() throws(CommandError) -> [String] {
        switch linker {
        // LLD is the one from the LLVM that rayo was built with.
        case .lld:
            // A missing LLD is reported with the ways to install it or to link without it.
            guard Self.isExecutableFile(tools.lld) else {
                throw .failed("""
                    can't find LLD at '\(tools.lld.path)': install LLD \(LLVMInstall.majorVersion), run \
                    'swift package purge-cache' and build rayo again, or link with --linker=platform
                    """)
            }
            // clang chooses the arguments it gives the linker by -fuse-ld, and runs the linker --ld-path names.
            return ["-fuse-ld=lld", "--ld-path=\(tools.lld.path)"]
        // The platform's linker is found where the platform keeps it.
        case .platform:
            return ["-fuse-ld=ld", "--ld-path=\(try platformLinker().path)"]
        }
    }

    /// Finds the platform's linker: on macOS, the `ld` of the developer tools `xcrun` selects, or `/usr/bin/ld`
    /// where it selects none; on Linux, `/usr/bin/ld`. Never an `ld` the search path happens to hold first.
    private func platformLinker() throws(CommandError) -> URL {
        // Find where the platform keeps its linker.
        #if canImport(Darwin)
        let found = try? runCapturingOutput(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "ld"])
        let path = found.flatMap { found in
            found.termination == .exited(0) ? found.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        let linker = URL(fileURLWithPath: path ?? "/usr/bin/ld")
        #else
        let linker = URL(fileURLWithPath: "/usr/bin/ld")
        #endif

        // A linker that isn't there, or can't be run, links nothing.
        guard Self.isExecutableFile(linker) else {
            throw .failed("can't find the platform's linker at '\(linker.path)'")
        }
        return linker
    }

    /// Whether `url` names a file, not a directory, that can be run.
    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Runs `executable` to completion, with what it writes captured or sent on as `output` asks.
    private func runSendingOutput(_ executable: URL, arguments: [String] = []) throws(CommandError) -> ProcessRun {
        switch output {
        case .captured: try runCapturingOutput(executable, arguments: arguments)
        case .inherited:
            ProcessRun(termination: try runAttached(executable, arguments: arguments), output: "", errors: "")
        }
    }

    /// Runs `executable` to completion, and returns how it ended and what it wrote.
    private func runCapturingOutput(
        _ executable: URL, arguments: [String] = [],
    ) throws(CommandError) -> ProcessRun {
        try Self.withTemporaryDirectory { directory throws(CommandError) in
            // Give each output stream a file, so that neither fills up and stalls the process while the other is read.
            let outputFile = directory.appendingPathComponent("stdout")
            let errorFile = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: outputFile.path, contents: nil)
            FileManager.default.createFile(atPath: errorFile.path, contents: nil)

            // Run the process on those files, with nothing to read, and give what it wrote.
            let process = newProcess(executable, arguments: arguments)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = try runOnHost { try FileHandle(forWritingTo: outputFile) }
            process.standardError = try runOnHost { try FileHandle(forWritingTo: errorFile) }
            let termination = try runToCompletion(process)
            return ProcessRun(termination: termination,
                              output: try runOnHost { try String(contentsOf: outputFile, encoding: .utf8) },
                              errors: try runOnHost { try String(contentsOf: errorFile, encoding: .utf8) })
        }
    }

    /// Runs `executable` to completion on `rayo`'s own standard input, output and error, and returns how it ended.
    private func runAttached(_ executable: URL, arguments: [String]) throws(CommandError) -> Termination {
        #if !os(Windows)
        // An interrupt from the terminal reaches the process and `rayo` alike. `rayo` outlives it, so that
        // it still removes its temporary files; a handled signal, unlike an ignored one, is reset in the process.
        let interrupt = signal(SIGINT) { _ in }
        let quit = signal(SIGQUIT) { _ in }
        defer {
            signal(SIGINT, interrupt)
            signal(SIGQUIT, quit)
        }
        #endif
        return try runToCompletion(newProcess(executable, arguments: arguments))
    }

    /// Makes a process, not yet run, that runs `executable` with `arguments` in the toolchain's environment.
    private func newProcess(_ executable: URL, arguments: [String] = []) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        return process
    }

    /// Runs `process` to its end, and returns how it ended.
    private func runToCompletion(_ process: Process) throws(CommandError) -> Termination {
        // `run` returns once the process starts, so wait for it to end.
        try runOnHost { try process.run() }
        process.waitUntilExit()

        // A process that a signal ended has the signal for its status.
        let status = process.terminationStatus
        return process.terminationReason == .uncaughtSignal ? .signaled(status) : .exited(status)
    }

    /// Runs `body` on a new, empty directory, and removes the directory once `body` ends.
    private static func withTemporaryDirectory<Value>(
        _ body: (URL) throws(CommandError) -> Value,
    ) throws(CommandError) -> Value {
        // Make the directory, under a name no other run of rayo takes.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayo-\(UUID().uuidString)", isDirectory: true)
        try runOnHost { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

        // Run the body on it, and remove it whether the body returns or throws.
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }
}

/// How a process that `Toolchain` ran ended, and what it wrote, where that was captured.
private struct ProcessRun {
    var termination: Termination
    var output: String
    var errors: String
}

/// How a process ended: with an exit code of its own, or by a signal.
private enum Termination: Equatable {
    case exited(Int32)
    case signaled(Int32)

    /// The exit code a shell reports for the process: its own, or 128 plus the signal that ended it.
    var exitCode: Int32 {
        switch self {
        case .exited(let exitCode): exitCode
        case .signaled(let signal): 128 + signal
        }
    }
}

/// Runs `operation`, a call into the host's files or processes, and gives what it gives, or fails with the
/// description of the error it throws.
private func runOnHost<Value>(_ operation: () throws -> Value) throws(CommandError) -> Value {
    do {
        return try operation()
    } catch {
        // The host's error stops the command, with the host's words for what went wrong.
        throw .failed(error.localizedDescription)
    }
}
