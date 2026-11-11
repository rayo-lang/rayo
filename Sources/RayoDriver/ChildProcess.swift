#if os(Windows)
import WinSDK
#endif
import Foundation

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
    func run() throws -> Termination {
        #if os(Windows)
        try runOnWindows()
        #else
        try runWithFoundation()
        #endif
    }

    #if !os(Windows)
    /// Runs the process as a Foundation `Process`, and returns how it ended.
    private func runWithFoundation() throws -> Termination {
        // Have Foundation run the process on the files given, and on `rayo`'s own for the rest.
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        if let standardInput { process.standardInput = standardInput }
        if let standardOutput { process.standardOutput = standardOutput }
        if let standardError { process.standardError = standardError }

        // `run` returns once the process starts, so wait for it to end.
        try process.run()
        process.waitUntilExit()

        // A process that a signal ended has the signal for its status.
        let status = process.terminationStatus
        return process.terminationReason == .uncaughtSignal ? .signaled(status) : .exited(status)
    }
    #endif
}

#if os(Windows)
extension ChildProcess {
    /// The attribute that names the handles a process inherits, which WinSDK defines with a macro Swift can't import.
    private static let inheritedHandlesAttribute = DWORD_PTR(0x0002_0002)

    /// Runs the process, started by Windows itself, and returns how it ended.
    private func runOnWindows() throws -> Termination {
        // Foundation closes the handle of a process it ran once the process ends, and reports an exception's code
        // without its two highest bits, so `rayo` starts the process itself and holds its handle until it has the code.
        let process = try start()
        defer { CloseHandle(process) }

        // Wait for the process to end, and read how it ended; a wait that fails would read a code the process
        // hasn't ended with.
        guard WaitForSingleObject(process, INFINITE) != WAIT_FAILED else { throw Self.windowsError(GetLastError()) }
        var code: DWORD = 0
        guard GetExitCodeProcess(process, &code) else { throw Self.windowsError(GetLastError()) }
        return Termination(windowsExitCode: code)
    }

    /// Starts the process, and returns its handle.
    private func start() throws -> HANDLE {
        // Give the process copies of its standard handles that it can inherit, and close them once it has its own.
        var nullDevice: FileHandle?
        let standardHandles = try [
            (standardInput, STD_INPUT_HANDLE), (standardOutput, STD_OUTPUT_HANDLE), (standardError, STD_ERROR_HANDLE),
        ].map { file, own in
            try Self.inheritableCopy(of: Self.handle(of: file, own: own, nullDevice: &nullDevice))
        }
        defer { standardHandles.forEach { if let handle = $0 { CloseHandle(handle) } } }

        // Start the process on those copies, with its command line and environment in the forms Windows takes them.
        let path = executable.path.replacingOccurrences(of: "/", with: "\\")
        var commandLine = Array(([path] + arguments).map(Self.quoted).joined(separator: " ").utf16) + [0]
        let flags = DWORD(EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT)
        let inheritsHandles = standardHandles.contains { $0 != nil }
        var started = PROCESS_INFORMATION()
        // A start that fails gives Windows's error at once, before freeing the memory it was given changes it.
        let failure = try Self.withStartupInfo(standardHandles: standardHandles) { startup in
            path.withCString(encodedAs: UTF16.self) { path in
                Self.environmentBlock(environment).withCString(encodedAs: UTF16.self) { environment in
                    CreateProcessW(path, &commandLine, nil, nil, inheritsHandles, flags,
                                   UnsafeMutableRawPointer(mutating: environment), nil, startup, &started)
                        ? nil : GetLastError()
                }
            }
        }
        if let failure { throw Self.windowsError(failure) }
        CloseHandle(started.hThread)
        return started.hProcess
    }

    /// The Windows handle that a process gets from `file` for one of its standard streams, or from `rayo`'s own
    /// standard handle `own` where `file` is nil. `nullDevice` holds the null device once a stream needs it.
    private static func handle(of file: FileHandle?, own: DWORD, nullDevice: inout FileHandle?) throws -> HANDLE? {
        switch file {
        // No file gives the process `rayo`'s own handle.
        case nil:
            return GetStdHandle(own)
        // `FileHandle.nullDevice` holds no handle, so the null device is opened, once for every stream that needs it.
        case let file? where file === FileHandle.nullDevice:
            let opened = try nullDevice ?? FileHandle(forUpdating: URL(fileURLWithPath: "NUL", isDirectory: false))
            nullDevice = opened
            return opened._handle
        // Any other file gives its own handle.
        case let file?:
            return file._handle
        }
    }

    /// A copy of `handle` that a process can inherit, or nil where `handle` is none, as for a standard handle that
    /// `rayo` lacks.
    private static func inheritableCopy(of handle: HANDLE?) throws -> HANDLE? {
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        var copy: HANDLE?
        let process = GetCurrentProcess()
        guard DuplicateHandle(process, handle, process, &copy, 0, true, DWORD(DUPLICATE_SAME_ACCESS)) else {
            throw windowsError(GetLastError())
        }
        return copy
    }

    /// Runs `body` on startup information that starts a process on `standardHandles`, and has it inherit no other
    /// handle, even one that a process `rayo` starts meanwhile inherits.
    private static func withStartupInfo<Value>(
        standardHandles: [HANDLE?], _ body: (UnsafeMutablePointer<STARTUPINFOW>) throws -> Value,
    ) throws -> Value {
        // Name the process's standard handles.
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.StartupInfo.dwFlags = DWORD(STARTF_USESTDHANDLES)
        startup.StartupInfo.hStdInput = standardHandles[0]
        startup.StartupInfo.hStdOutput = standardHandles[1]
        startup.StartupInfo.hStdError = standardHandles[2]
        // Windows reads the whole of the extended startup information through a pointer to its first field.
        func withStartup() throws -> Value {
            try withUnsafeMutablePointer(to: &startup) { startup in
                try startup.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1, body)
            }
        }

        // A process that inherits no handle needs no list of them.
        var inherited = standardHandles.compactMap { $0 }
        guard !inherited.isEmpty else { return try withStartup() }

        // List the handles the process inherits, in memory of the size Windows asks for, which outlasts the list.
        var size: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &size)
        return try inherited.withUnsafeMutableBufferPointer { inherited in
            try withUnsafeTemporaryAllocation(byteCount: Int(size), alignment: 16) { memory in
                let list = LPPROC_THREAD_ATTRIBUTE_LIST(memory.baseAddress!)
                guard InitializeProcThreadAttributeList(list, 1, 0, &size) else {
                    throw windowsError(GetLastError())
                }
                defer { DeleteProcThreadAttributeList(list) }
                let byteCount = SIZE_T(inherited.count * MemoryLayout<HANDLE>.stride)
                guard UpdateProcThreadAttribute(list, 0, inheritedHandlesAttribute, inherited.baseAddress, byteCount,
                                                nil, nil) else { throw windowsError(GetLastError()) }
                startup.lpAttributeList = list
                return try withStartup()
            }
        }
    }

    /// `argument` written so that the C runtime reads it back from a command line as it is.
    private static func quoted(_ argument: String) -> String {
        // An argument with no space, tab or quote in it reads back as it is, unless it's empty.
        guard argument.isEmpty || argument.contains(where: { " \t\n\u{0B}\"".contains($0) }) else { return argument }

        // In quotes, a backslash is read as it is, except in a run of them before a quote, where each pair is read
        // as one, and an odd one escapes the quote.
        var quoted = "\""
        var backslashes = 0
        for character in argument {
            switch character {
            // A run of backslashes is written once it's known whether a quote ends it.
            case "\\":
                backslashes += 1
            // A quote is escaped, and so is each backslash before it.
            case "\"":
                quoted += String(repeating: "\\", count: 2 * backslashes + 1) + "\""
                backslashes = 0
            // Backslashes before anything else are written as they are.
            default:
                quoted += String(repeating: "\\", count: backslashes) + String(character)
                backslashes = 0
            }
        }

        // The backslashes before the closing quote are each escaped, so that the quote still closes the argument.
        return quoted + String(repeating: "\\", count: 2 * backslashes) + "\""
    }

    /// `environment` as Windows takes it: a block of `name=value` strings, sorted by name in any case, each ended by a
    /// 0, then a 0 that ends the block.
    private static func environmentBlock(_ environment: [String: String]) -> String {
        let sorted = environment.sorted { $0.key.uppercased() < $1.key.uppercased() }
        return sorted.map { "\($0.key)=\($0.value)\0" }.joined() + "\0"
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
#endif
