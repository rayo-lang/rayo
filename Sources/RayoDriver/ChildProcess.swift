#if os(Windows)
import ucrt
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import Subprocess

/// A process that `rayo` runs to its end: an executable, with its arguments and environment, on the files it reads
/// and writes.
struct ChildProcess {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    /// The files the process has for its standard input, output and error; nil gives it `rayo`'s own.
    var standardInput: FileHandle? = nil
    var standardOutput: FileHandle? = nil
    var standardError: FileHandle? = nil

    /// Runs the process, waits for it to end, and returns how it ended.
    func run() async throws -> Termination {
        // Give the process copies of the descriptors for its standard streams, which are closed by the time it ends.
        var descriptors: [Int32] = []
        defer { descriptors.forEach(Self.closeCopy) }
        let files = [(standardInput, StandardStream.input), (standardOutput, .output), (standardError, .error)]
        for (file, stream) in files {
            descriptors.append(try Self.descriptor(for: file, stream: stream))
        }

        // Run the process on them, in exactly its environment.
        let status: TerminationStatus
        do {
            status = try await Subprocess.run(
                .path(.init(executable.path)), arguments: .init(arguments),
                environment: .custom(Self.variables(environment)),
                input: .fileDescriptor(.init(rawValue: descriptors[0]), closeAfterSpawningProcess: false),
                output: .fileDescriptor(.init(rawValue: descriptors[1]), closeAfterSpawningProcess: false),
                error: .fileDescriptor(.init(rawValue: descriptors[2]), closeAfterSpawningProcess: false),
            ) { _ in
                // A started process has descriptors of its own. Windows lets another process inherit a copy while it
                // is open, so the copies close as soon as this one starts, and not when it ends.
                descriptors.forEach(Self.closeCopy)
                descriptors = []
            }.terminationStatus
        } catch {
            // swift-subprocess says what went wrong in its description, and not in its localized one.
            throw NSError(domain: "Subprocess", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(error)"])
        }
        return Self.termination(status)
    }

    /// A copy of the descriptor that the process gets for `stream` from `file`, which the caller closes.
    private static func descriptor(for file: FileHandle?, stream: StandardStream) throws -> Int32 {
        switch file {
        // No file gives the process `rayo`'s own stream, or the null device where `rayo` lacks it.
        case nil: try copyOfOwn(stream) ?? copyOfNullDevice()
        // `FileHandle.nullDevice` holds no descriptor, so the null device is opened for the process.
        case let file? where file === FileHandle.nullDevice: try copyOfNullDevice()
        case let file?: try copy(of: file)
        }
    }

    /// A copy of a descriptor for the null device, which the caller closes.
    private static func copyOfNullDevice() throws -> Int32 {
        #if os(Windows)
        let path = "NUL"
        #else
        let path = "/dev/null"
        #endif
        return try copy(of: FileHandle(forUpdating: URL(fileURLWithPath: path, isDirectory: false)))
    }

    /// `environment` keyed as swift-subprocess takes it. Windows names a variable in any case, so of two names that
    /// differ only in case, one is kept.
    private static func variables(_ environment: [String: String]) -> [Environment.Key: String] {
        let pairs = environment.map { (Environment.Key(stringLiteral: $0.key), $0.value) }
        return Dictionary(pairs) { first, _ in first }
    }

    /// How a process ended that swift-subprocess reports ended with `status`.
    private static func termination(_ status: TerminationStatus) -> Termination {
        switch status {
        #if os(Windows)
        // Windows ends a process with a code alone, which may be an exception's; it has no signals.
        case .exited(let code), .signaled(let code): Termination(windowsExitCode: code)
        #else
        case .exited(let exitCode): .exited(exitCode)
        case .signaled(let signal): .signaled(signal)
        #endif
        }
    }
}

extension ChildProcess {
    /// One of a process's standard streams, by the C library's number for it.
    private enum StandardStream: Int32 {
        case input, output, error
    }
}

#if os(Windows)
extension ChildProcess {
    /// A copy of the descriptor for `rayo`'s own `stream`, which the caller closes, or nil where `rayo` lacks it.
    private static func copyOfOwn(_ stream: StandardStream) throws -> Int32? {
        // The C library gives a stream `rayo` lacks a descriptor that holds no handle, so Windows is asked for it.
        let handle = switch stream {
        case .input: GetStdHandle(STD_INPUT_HANDLE)
        case .output: GetStdHandle(STD_OUTPUT_HANDLE)
        case .error: GetStdHandle(STD_ERROR_HANDLE)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        return try copy(of: handle)
    }

    /// A copy of the descriptor for `file`, which the caller closes.
    private static func copy(of file: FileHandle) throws -> Int32 {
        try copy(of: file._handle)
    }

    /// A C library descriptor for a copy of `handle`, which the caller closes. The descriptor owns the handle it
    /// holds, so it holds a copy, and `handle` stays open for whoever owns it.
    private static func copy(of handle: HANDLE) throws -> Int32 {
        // Copy the handle.
        var copy: HANDLE?
        let process = GetCurrentProcess()
        guard DuplicateHandle(process, handle, process, &copy, 0, false, DWORD(DUPLICATE_SAME_ACCESS)), let copy else {
            throw windowsError(GetLastError())
        }

        // Have the C library hold it, or close it where the library can't.
        let descriptor = _open_osfhandle(Int(bitPattern: copy), 0)
        guard descriptor != -1 else {
            CloseHandle(copy)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EMFILE)
        }
        return descriptor
    }

    /// Closes `descriptor`, and the handle it holds.
    private static func closeCopy(_ descriptor: Int32) {
        _ = _close(descriptor)
    }

    /// The Windows error `code`, in Windows's words.
    private static func windowsError(_ code: DWORD) -> NSError {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let flags = DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS)
        let length = Int(FormatMessageW(flags, nil, code, 0, &buffer, DWORD(buffer.count), nil))
        let message = String(decoding: buffer[..<length], as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return NSError(domain: "Windows", code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Windows error \(code)" : message])
    }
}
#else
extension ChildProcess {
    /// A copy of the descriptor for `rayo`'s own `stream`, which the caller closes, or nil where `rayo` lacks it.
    private static func copyOfOwn(_ stream: StandardStream) throws -> Int32? {
        let descriptor = copy(of: stream.rawValue)
        // A stream `rayo` lacks is a descriptor it hasn't open.
        if descriptor == -1 && errno == EBADF { return nil }
        return try checked(descriptor)
    }

    /// A copy of the descriptor for `file`, which the caller closes.
    private static func copy(of file: FileHandle) throws -> Int32 {
        try checked(copy(of: file.fileDescriptor))
    }

    /// A copy of `descriptor`, or -1 where it can't be copied. The copy closes on `exec`, so that no process
    /// inherits it but the one whose standard stream it becomes.
    private static func copy(of descriptor: Int32) -> Int32 {
        fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
    }

    /// `descriptor`, which a call gave, or the error that call set where it gave none.
    private static func checked(_ descriptor: Int32) throws -> Int32 {
        guard descriptor != -1 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EBADF) }
        return descriptor
    }

    /// Closes `descriptor`.
    private static func closeCopy(_ descriptor: Int32) {
        _ = close(descriptor)
    }
}
#endif
