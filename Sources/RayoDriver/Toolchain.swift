#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import RayoLLVM

/// The host tools that link object code into an executable and run it.
struct Toolchain {
    var tools: Driver.LinkTools
    var linker: Linker
    /// The environment that clang and a program run in.
    var environment: [String: String]

    /// Links `objectCode` with the C library into an executable at `output`.
    func link(_ objectCode: [UInt8], to output: URL) throws(CompilationError) {
        // A link needs clang, which drives it, and the arguments that have clang run the linker asked for.
        guard Self.isExecutableFile(tools.clang) else {
            throw .failed("can't find clang at '\(tools.clang.path)'")
        }
        let linkerArguments = try linkerArguments()

        // Write the object code to a file for clang to read, in a directory that goes once the link ends.
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let object = directory.appendingPathComponent("program.o")
        try runOnHost { try Data(objectCode).write(to: object) }

        // Have clang link the object file into the executable.
        let result = try runCapturingOutput(tools.clang, arguments: linkerArguments + [object.path, "-o", output.path])
        // A link that clang fails reports what clang wrote, without its last newline.
        if result.exitCode != 0 {
            let errors = result.errors.hasSuffix("\n") ? String(result.errors.dropLast()) : result.errors
            throw .failed("clang failed:\n\(errors)")
        }
    }

    /// Links `objectCode` into a temporary executable, runs it, and removes it.
    func linkAndRun(_ objectCode: [UInt8], output: Driver.ProgramOutput) throws(CompilationError) -> Driver.Result {
        // Link the executable in a directory that goes once the run ends.
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("program")
        try link(objectCode, to: executable)

        // Run it, with what it writes captured or sent on as `output` asks.
        return switch output {
        case .captured: try runCapturingOutput(executable)
        case .inherited: Driver.Result(exitCode: try runAttached(executable), output: "", errors: "")
        }
    }

    /// The arguments that have clang link with `linker`.
    private func linkerArguments() throws(CompilationError) -> [String] {
        switch linker {
        // LLD is the one from the LLVM that rayoc was built with.
        case .lld:
            // A missing LLD is reported with the ways to install it or to link without it.
            guard Self.isExecutableFile(tools.lld) else {
                throw .failed("""
                    can't find LLD at '\(tools.lld.path)': install LLD \(LLVMInstall.majorVersion), run \
                    'swift package purge-cache' and build rayoc again, or link with --linker=platform
                    """)
            }
            // clang chooses the arguments it gives the linker by -fuse-ld, and runs the linker --ld-path names.
            return ["-fuse-ld=lld", "--ld-path=\(tools.lld.path)"]
        // The platform's linker is found where the platform keeps it.
        case .platform:
            return ["-fuse-ld=ld", "--ld-path=\(try platformLinker().path)"]
        }
    }

    /// The platform's linker: on macOS, the `ld` of the developer tools `xcrun` selects, or `/usr/bin/ld` where
    /// it selects none; on Linux, `/usr/bin/ld`. Never an `ld` the search path happens to hold first.
    private func platformLinker() throws(CompilationError) -> URL {
        // Find where the platform keeps its linker.
        #if canImport(Darwin)
        let found = try? runCapturingOutput(URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--find", "ld"])
        let path = found.flatMap { $0.exitCode == 0 ? $0.output.trimmingCharacters(in: .whitespacesAndNewlines) : nil }
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

    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    /// Runs `executable` to completion, and returns its exit code and what it wrote.
    private func runCapturingOutput(
        _ executable: URL, arguments: [String] = [],
    ) throws(CompilationError) -> Driver.Result {
        // Give each output stream a temporary file, so that neither can fill up and stall the process while the
        // other is read.
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputFile = directory.appendingPathComponent("stdout")
        let errorFile = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)

        // Run the process on those files, with nothing to read, and give what it wrote.
        let process = newProcess(executable, arguments: arguments)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = try runOnHost { try FileHandle(forWritingTo: outputFile) }
        process.standardError = try runOnHost { try FileHandle(forWritingTo: errorFile) }
        let exitCode = try runToCompletion(process)
        return Driver.Result(exitCode: exitCode,
                             output: try runOnHost { try String(contentsOf: outputFile, encoding: .utf8) },
                             errors: try runOnHost { try String(contentsOf: errorFile, encoding: .utf8) })
    }

    /// Runs `executable` to completion on `rayoc`'s own standard input, output and error, and returns its
    /// exit code.
    private func runAttached(_ executable: URL) throws(CompilationError) -> Int32 {
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
    private func runToCompletion(_ process: Process) throws(CompilationError) -> Int32 {
        // Run the process, and wait for it to end.
        try runOnHost { try process.run() }
        process.waitUntilExit()

        let status = process.terminationStatus
        // A process that a signal ended exits with 128 plus the signal, as a shell reports it.
        return process.terminationReason == .uncaughtSignal ? 128 + status : status
    }

    /// Creates a new, empty directory, which the caller removes.
    private static func temporaryDirectory() throws(CompilationError) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rayoc-\(UUID().uuidString)", isDirectory: true)
        try runOnHost { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }
}

/// Runs `operation`, a call into the host's files or processes, and gives what it gives, or fails with the
/// description of the error it throws.
private func runOnHost<Value>(_ operation: () throws -> Value) throws(CompilationError) -> Value {
    do {
        return try operation()
    } catch {
        // The host's error stops the compile, with the host's words for what went wrong.
        throw .failed(error.localizedDescription)
    }
}
