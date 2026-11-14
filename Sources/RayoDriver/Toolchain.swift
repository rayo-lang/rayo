#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
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

    /// Has `rayoc` check the source file at `path`, failing on a warning where `warningsAreErrors`, and returns what
    /// `rayoc` wrote to its standard error, where `output` captures it.
    func check(_ path: String, warningsAreErrors: Bool) throws(CommandError) -> String {
        try runCompiler(Self.warningOptions(warningsAreErrors) + ["--check", "--", path])
    }

    /// Has `rayoc` compile the source file at `path` to object code in `mode`, failing on a warning where
    /// `warningsAreErrors`, and runs `body` on the object file, which is removed once `body` ends. Returns what `body`
    /// returns, and what `rayoc` wrote to its standard error, where `output` captures it.
    func compile<Value>(
        _ path: String, mode: BuildMode, warningsAreErrors: Bool, _ body: (URL) throws(CommandError) -> Value,
    ) throws(CommandError) -> (value: Value, errors: String) {
        try Self.withTemporaryDirectory { directory throws(CommandError) in
            // Have `rayoc` write the object file inside the directory, so it goes with the directory.
            let objectFile = directory.appendingPathComponent("program.o")
            let options = Self.warningOptions(warningsAreErrors) + [mode.rawValue]
            let errors = try runCompiler(options + ["-o", objectFile.path, "--", path])

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
        let arguments = linkerArguments + Self.stackArguments + [objectFile.path, "-o", executable.path]
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
            let executable = directory.appendingPathComponent(Executable.fileName("program"))
            try link(objectFile, to: executable)

            // Run it, and give how it ended and what of its output was captured.
            let run = try runSendingOutput(executable)
            return CommandResult(exitCode: run.termination.exitCode, output: run.output, errors: run.errors)
        }
    }

    /// The options that have `rayoc` fail on a warning where `warningsAreErrors`.
    private static func warningOptions(_ warningsAreErrors: Bool) -> [String] {
        warningsAreErrors ? ["--warnings-as-errors"] : []
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
        // A `rayoc` that a signal or an exception ended couldn't say so, so `rayo` says how it ended.
        case .signaled, .raisedException:
            throw .compileFailed(exitCode: run.termination.exitCode,
                                 errors: run.errors + "rayo: rayoc \(run.termination)\n")
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
            #if os(Windows)
            // clang's driver for MSVC takes no --ld-path, and finds a linker that -fuse-ld names by its path under
            // a name with the target's triple before it. It looks for `lld-link` first in the directories -B names.
            return ["-fuse-ld=lld", "-B\(tools.lld.deletingLastPathComponent().path)"]
            #else
            // clang chooses the arguments it gives the linker by -fuse-ld, and runs the linker --ld-path names.
            return ["-fuse-ld=lld", "--ld-path=\(tools.lld.path)"]
            #endif
        // The platform's linker is found where the platform keeps it.
        case .platform:
            #if os(Windows)
            // clang runs the `link.exe` of the Visual Studio whose libraries it links, not one on the search path.
            return ["-fuse-ld=link"]
            #else
            // clang runs the `ld` that --ld-path names, which is where the platform keeps its linker.
            return ["-fuse-ld=ld", "--ld-path=\(try platformLinker().path)"]
            #endif
        }
    }

    #if !os(Windows)
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
    #endif

    // What every link gives the linker for the size of a program's main thread's stack.
    #if os(Windows)
    // Windows reserves 1 MiB where macOS and Linux give 8 MiB, and a debug build's frames are larger on x64 Windows,
    // which has each call reserve 32 bytes for its callee. A stack of 16 MiB lets a program recurse at least as deep.
    private static let stackArguments = ["-Wl,/STACK:16777216"]
    #else
    private static let stackArguments: [String] = []
    #endif

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
            // `FileManager.createFile` renames a temporary file into place, and returns false unreported where
            // Windows refuses the rename, so each file is written in place.
            try runOnHost { try Data().write(to: outputFile) }
            try runOnHost { try Data().write(to: errorFile) }

            // Run the process on those files, with nothing to read, and give what it wrote.
            var process = childProcess(executable, arguments: arguments)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = try runOnHost { try FileHandle(forWritingTo: outputFile) }
            process.standardError = try runOnHost { try FileHandle(forWritingTo: errorFile) }
            let termination = try runOnHost { try process.run() }
            return ProcessRun(termination: termination,
                              output: try runOnHost { try String(contentsOf: outputFile, encoding: .utf8) },
                              errors: try runOnHost { try String(contentsOf: errorFile, encoding: .utf8) })
        }
    }

    /// Runs `executable` to completion on `rayo`'s own standard input, output and error, and returns how it ended.
    private func runAttached(_ executable: URL, arguments: [String]) throws(CommandError) -> Termination {
        #if os(Windows)
        // Ctrl-C and Ctrl-Break reach every process of the console, `rayo` too. `rayo` outlives them, so that it
        // still removes its temporary files; the process inherits no handler, so it still ends by them.
        SetConsoleCtrlHandler(ignoringInterrupts, true)
        defer { SetConsoleCtrlHandler(ignoringInterrupts, false) }
        #else
        // An interrupt from the terminal reaches the process and `rayo` alike. `rayo` outlives it, so that
        // it still removes its temporary files; a handled signal, unlike an ignored one, is reset in the process.
        let interrupt = signal(SIGINT) { _ in }
        let quit = signal(SIGQUIT) { _ in }
        defer {
            signal(SIGINT, interrupt)
            signal(SIGQUIT, quit)
        }
        #endif
        let process = childProcess(executable, arguments: arguments)
        return try runOnHost { try process.run() }
    }

    /// The process that runs `executable` with `arguments` in the toolchain's environment, on `rayo`'s own standard
    /// input, output and error.
    private func childProcess(_ executable: URL, arguments: [String]) -> ChildProcess {
        ChildProcess(executable: executable, arguments: arguments, environment: environment)
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

#if os(Windows)
/// Handles Ctrl-C and Ctrl-Break so they don't end `rayo`, and passes every other console event on.
private let ignoringInterrupts: PHANDLER_ROUTINE = { event in
    WindowsBool(event == DWORD(CTRL_C_EVENT) || event == DWORD(CTRL_BREAK_EVENT))
}
#endif

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
