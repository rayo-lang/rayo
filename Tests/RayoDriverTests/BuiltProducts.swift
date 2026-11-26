import Foundation
import Testing
import RayoDriver
import RayoLLVMInstall
#if os(Windows)
import WinSDK
#endif

/// Marks the bundle these tests build into, so that its place on disk can be found.
private final class TestBundle {}

/// The executable `name` that the package's build puts beside these tests: `rayo`, `rayoc` or `tool-stand-in`.
func builtProduct(_ name: String) -> URL {
    let bundle = Bundle(for: TestBundle.self).bundleURL
    // On macOS the tests are an `.xctest` bundle beside the products; elsewhere they are an executable among them.
    let products = bundle.pathExtension == "xctest" ? bundle.deletingLastPathComponent() : bundle
    return products.appendingPathComponent(Executable.fileName(name))
}

/// Runs the `rayo` at `executable`, the built one unless another is named, with `arguments` in `directory`, as a user
/// would there, and gives what it exits with and what it writes. A run that can't start is recorded as an issue, and
/// gives exit code -1.
func rayo(_ arguments: [String], in directory: URL, running executable: URL = builtProduct("rayo")) -> CommandResult {
    do {
        // Give each output stream a file, so that neither fills up and stalls the run while the other is read.
        let runID = UUID().uuidString
        // The names are this call's own: Windows won't rewrite a file while another process, such as a child of an
        // earlier call or a virus scanner, holds it open.
        let outputFile = directory.appendingPathComponent(".rayo-\(runID)-stdout")
        let errorFile = directory.appendingPathComponent(".rayo-\(runID)-stderr")
        // `FileManager.createFile` renames a temporary file into place, and returns false unreported where Windows
        // refuses the rename, so each file is written in place.
        try Data().write(to: outputFile)
        try Data().write(to: errorFile)

        // Run `rayo` there, and give what it wrote.
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = try FileHandle(forWritingTo: outputFile)
        let errors = try FileHandle(forWritingTo: errorFile)
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        // The files are read once this process holds them open no longer.
        try output.close()
        try errors.close()
        return CommandResult(exitCode: process.terminationStatus,
                             output: try String(contentsOf: outputFile, encoding: .utf8),
                             errors: try String(contentsOf: errorFile, encoding: .utf8))
    } catch {
        Issue.record(error)
        return CommandResult(exitCode: -1, output: "", errors: "")
    }
}

#if os(Windows)
/// Runs the built `rayo` with `arguments` in `directory` and `environment`, on a console of its own with no window,
/// so that a console event raised there reaches no process of these tests, and gives the code it exits with.
/// `arguments` must need no quotes.
func rayoOnConsoleOfItsOwn(_ arguments: [String], in directory: URL, environment: [String: String]) throws -> DWORD {
    try runRayo(arguments, in: directory, environment: environment, running: builtProduct("rayo"),
                creationFlags: DWORD(CREATE_NO_WINDOW), startupFlags: 0)
}

/// Runs the `rayo` at `executable` with `arguments` in `directory` and `environment`, with no standard input, and
/// gives the code it exits with. A process without a console can't have only some standard handles, so it has no
/// standard output or error either. `arguments` must need no quotes.
func rayoWithoutStandardInput(
    _ arguments: [String], in directory: URL, environment: [String: String], running executable: URL,
) throws -> Int32 {
    // Windows gives a process that has a console the console's handles in place of empty ones, so `rayo` has none,
    // and its startup information names empty standard handles.
    let code = try runRayo(arguments, in: directory, environment: environment, running: executable,
                           creationFlags: DWORD(DETACHED_PROCESS), startupFlags: DWORD(STARTF_USESTDHANDLES))
    return Int32(bitPattern: code)
}

/// Runs the `rayo` at `executable` with `arguments` in `directory` and `environment`, started with `creationFlags` and
/// with startup information of `startupFlags`, and gives the code it exits with. `arguments` must need no quotes.
private func runRayo(
    _ arguments: [String], in directory: URL, environment: [String: String], running executable: URL,
    creationFlags: DWORD, startupFlags: DWORD,
) throws -> DWORD {
    // Windows takes the command line as one string, and the environment as one block of `name=value` strings, each
    // ended by a 0, then a 0 that ends the block, sorted by name in any case.
    var commandLine = Array((["\"\(executable.path)\""] + arguments).joined(separator: " ").utf16) + [0]
    let block = environment.sorted { $0.key.uppercased() < $1.key.uppercased() }
        .map { "\($0.key)=\($0.value)\0" }.joined() + "\0"

    // Start `rayo`, inheriting no handle of these tests.
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    startup.dwFlags = startupFlags
    var started = PROCESS_INFORMATION()
    let didStart = block.withCString(encodedAs: UTF16.self) { block in
        directory.path.withCString(encodedAs: UTF16.self) { directory in
            CreateProcessW(nil, &commandLine, nil, nil, false, creationFlags | DWORD(CREATE_UNICODE_ENVIRONMENT),
                           UnsafeMutableRawPointer(mutating: block), directory, &startup, &started)
        }
    }
    try #require(didStart, "rayo didn't start: Windows error \(GetLastError())")
    defer {
        CloseHandle(started.hThread)
        CloseHandle(started.hProcess)
    }

    // Wait for `rayo` to end, and give its exit code; a `rayo` that hasn't ended in five minutes is stopped, and
    // fails the test, rather than leaving the tests to wait on it.
    if WaitForSingleObject(started.hProcess, 300_000) == DWORD(WAIT_TIMEOUT) {
        TerminateProcess(started.hProcess, 1)
        Issue.record("rayo didn't end within five minutes")
    }
    var code: DWORD = 0
    try #require(GetExitCodeProcess(started.hProcess, &code), "no exit code: Windows error \(GetLastError())")
    return code
}

extension [String: String] {
    /// This environment, with the variable `name`, in whatever case its name is written, set to `value`.
    func setting(_ name: String, to value: String) -> [String: String] {
        var environment = filter { $0.key.uppercased() != name.uppercased() }
        environment[name] = value
        return environment
    }
}
#else
/// Runs the `rayo` at `executable` with `arguments` in `directory` and `environment`, with its standard input closed,
/// and gives the code it exits with.
func rayoWithoutStandardInput(
    _ arguments: [String], in directory: URL, environment: [String: String], running executable: URL,
) throws -> Int32 {
    // Foundation can't close a standard stream for a process it runs, so a shell closes it and becomes `rayo`.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "exec \"$0\" \"$@\" <&-", executable.path] + arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
#endif
