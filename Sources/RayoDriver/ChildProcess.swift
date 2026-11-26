#if os(Windows)
import CRT
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
internal import Subprocess

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
        // Give the process copies of the descriptors for its standard streams.
        let copies = try StreamCopies(input: Self.copy(for: standardInput, stream: .input),
                                      output: Self.copy(for: standardOutput, stream: .output),
                                      error: Self.copy(for: standardError, stream: .error))
        let inputDescriptor = copies.input.descriptor
        let outputDescriptor = copies.output.descriptor
        let errorDescriptor = copies.error.descriptor
        var openCopies = Optional(copies)

        // Run the process on them, in exactly its environment.
        let status: TerminationStatus
        do {
            status = try await Subprocess.run(
                .path(.init(executable.path)), arguments: .init(arguments),
                environment: .custom(Self.variables(environment)),
                input: .fileDescriptor(.init(rawValue: inputDescriptor), closeAfterSpawningProcess: false),
                output: .fileDescriptor(.init(rawValue: outputDescriptor), closeAfterSpawningProcess: false),
                error: .fileDescriptor(.init(rawValue: errorDescriptor), closeAfterSpawningProcess: false),
            ) { _ in
                // A started process has descriptors of its own, and Windows lets another process inherit a copy while
                // it is open, so the copies close as soon as this one starts. swift-subprocess would close only the
                // handle a Windows descriptor holds, so the copies close themselves.
                _ = openCopies.take()
            }.terminationStatus
        } catch {
            // swift-subprocess says what went wrong in its description, and not in its localized one.
            throw NSError(domain: "Subprocess", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(error)"])
        }
        return Self.termination(status)
    }

    /// A copy of the descriptor that the process gets for `stream` from `file`.
    private static func copy(for file: FileHandle?, stream: StandardStream) throws -> DescriptorCopy {
        switch file {
        // No file gives the process `rayo`'s own stream, or the null device where `rayo` lacks it.
        case nil: try copyOfOwn(stream) ?? copyOfNullDevice()
        // `FileHandle.nullDevice` holds no descriptor, so the null device is opened for the process.
        case let file? where file === FileHandle.nullDevice: try copyOfNullDevice()
        case let file?: try copy(of: file)
        }
    }

    /// A copy of a descriptor for the null device.
    private static func copyOfNullDevice() throws -> DescriptorCopy {
        #if os(Windows)
        let path = "NUL"
        #else
        let path = "/dev/null"
        #endif
        return try copy(of: FileHandle(forUpdating: URL(fileURLWithPath: path, isDirectory: false)))
    }

    /// `environment` keyed as swift-subprocess takes it. Windows names a variable in any case, so of two names that
    /// differ only in case, the first in sorted order is kept.
    private static func variables(_ environment: [String: String]) -> [Environment.Key: String] {
        let pairs = environment.sorted { $0.key < $1.key }.map { (Environment.Key(stringLiteral: $0.key), $0.value) }
        return Dictionary(pairs) { first, _ in first }
    }

    /// How a process ended that swift-subprocess reports ended with `status`.
    private static func termination(_ status: TerminationStatus) -> Termination {
        switch status {
        #if os(Windows)
        // Windows ends a process with a code alone, which may be an exception's.
        case .exited(let code): Termination(windowsExitCode: code)
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

    /// A copy of a file descriptor, which closes when the copy goes.
    private struct DescriptorCopy: ~Copyable {
        let descriptor: Int32

        deinit { ChildProcess.closeDescriptor(descriptor) }
    }

    /// The copies of the descriptors that a process gets for its standard input, output and error.
    private struct StreamCopies: ~Copyable {
        let input: DescriptorCopy
        let output: DescriptorCopy
        let error: DescriptorCopy
    }
}

#if os(Windows)
extension ChildProcess {
    /// A copy of the descriptor for `rayo`'s own `stream`, or nil where `rayo` lacks it.
    private static func copyOfOwn(_ stream: StandardStream) throws -> DescriptorCopy? {
        // The C library gives a stream `rayo` lacks a descriptor that holds no handle, so Windows is asked for it.
        let handle = switch stream {
        case .input: GetStdHandle(STD_INPUT_HANDLE)
        case .output: GetStdHandle(STD_OUTPUT_HANDLE)
        case .error: GetStdHandle(STD_ERROR_HANDLE)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        return try copy(of: handle)
    }

    /// A copy of the descriptor for `file`.
    private static func copy(of file: FileHandle) throws -> DescriptorCopy {
        try copy(of: file._handle)
    }

    /// A C library descriptor for a copy of `handle`. The descriptor owns the handle it holds, so it holds a copy,
    /// and `handle` stays open for whoever owns it.
    private static func copy(of handle: HANDLE) throws -> DescriptorCopy {
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
        return DescriptorCopy(descriptor: descriptor)
    }

    /// Closes `descriptor`, and the handle it holds.
    private static func closeDescriptor(_ descriptor: Int32) {
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
    /// A copy of the descriptor for `rayo`'s own `stream`, or nil where `rayo` lacks it.
    private static func copyOfOwn(_ stream: StandardStream) throws -> DescriptorCopy? {
        let descriptor = copy(of: stream.rawValue)
        // A stream `rayo` lacks is a descriptor it doesn't have open.
        if descriptor == -1 && errno == EBADF { return nil }
        return try checked(descriptor)
    }

    /// A copy of the descriptor for `file`.
    private static func copy(of file: FileHandle) throws -> DescriptorCopy {
        try checked(copy(of: file.fileDescriptor))
    }

    /// A copy of `descriptor`, or -1 where it can't be copied. The copy closes on `exec`, so that no process
    /// inherits it but the one whose standard stream it becomes.
    private static func copy(of descriptor: Int32) -> Int32 {
        fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
    }

    /// The copy `descriptor`, which a call gave, or the error that call set where it gave none.
    private static func checked(_ descriptor: Int32) throws -> DescriptorCopy {
        guard descriptor != -1 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EBADF) }
        return DescriptorCopy(descriptor: descriptor)
    }

    /// Closes `descriptor`.
    private static func closeDescriptor(_ descriptor: Int32) {
        _ = close(descriptor)
    }
}
#endif
