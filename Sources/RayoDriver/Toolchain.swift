#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import RayoLLVM

extension Driver {
    /// The clang that drives the link of a program, and the LLD it links with unless the platform's linker is asked
    /// for.
    public struct LinkTools: Sendable {
        public var clang: URL
        /// The LLD for the host's object file format: `ld64.lld` for Mach-O, and `ld.lld` for ELF.
        public var lld: URL

        public init(clang: URL, lld: URL) {
            self.clang = clang
            self.lld = lld
        }

        /// The clang and LLD of the LLVM install that `rayoc` was built against.
        public static let installed = LinkTools(
            clang: URL(fileURLWithPath: LLVMInstall.toolDirectory).appendingPathComponent("clang"),
            lld: URL(fileURLWithPath: LLVMInstall.lldDirectory).appendingPathComponent(hostLLD))

        #if canImport(Darwin)
        private static let hostLLD = "ld64.lld"
        #else
        private static let hostLLD = "ld.lld"
        #endif
    }
}

/// The linker that clang links a program with.
enum Linker: String {
    /// LLD, which links the same way on every platform.
    case lld
    /// The platform's own: Apple's `ld` on macOS, and the system `ld` on Linux.
    case platform
}

/// The host tools that link object code into an executable and run it.
struct Toolchain {
    var tools: Driver.LinkTools
    var linker: Linker
    /// The environment that clang and a program run in.
    var environment: [String: String]

    /// Links `objectCode` with the C library into an executable at `output`.
    func link(_ objectCode: [UInt8], to output: URL) throws {
        guard Self.isExecutableFile(tools.clang) else { throw Failure("can't find clang at '\(tools.clang.path)'") }
        let linkerArguments = try linkerArguments()
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let object = directory.appendingPathComponent("program.o")
        try Data(objectCode).write(to: object)
        let result = try runCapturingOutput(tools.clang, arguments: linkerArguments + [object.path, "-o", output.path])
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

    /// The arguments that have clang link with `linker`.
    private func linkerArguments() throws(Failure) -> [String] {
        switch linker {
        case .lld:
            guard Self.isExecutableFile(tools.lld) else {
                throw Failure("can't find LLD at '\(tools.lld.path)': install it, or link with --linker=platform")
            }
            // clang chooses the arguments it gives the linker by -fuse-ld, and runs the linker --ld-path names.
            return ["-fuse-ld=lld", "--ld-path=\(tools.lld.path)"]
        case .platform:
            // -fuse-ld=ld names the platform's linker, even for a clang built to prefer another.
            return ["-fuse-ld=ld"]
        }
    }

    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
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
