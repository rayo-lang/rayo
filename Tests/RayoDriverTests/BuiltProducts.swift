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

/// Runs the built `rayo` with `arguments` in `directory`, as a user would there, and gives what it exits with and
/// what it writes. A run that can't start is recorded as an issue, and gives exit code -1.
func rayo(_ arguments: [String], in directory: URL) -> CommandResult {
    do {
        // Give each output stream a file, so that neither fills up and stalls the run while the other is read.
        let outputFile = directory.appendingPathComponent(".rayo-stdout")
        let errorFile = directory.appendingPathComponent(".rayo-stderr")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)

        // Run `rayo` there, and give what it wrote.
        let process = Process()
        process.executableURL = builtProduct("rayo")
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
    // Windows takes the command line as one string, and the environment as one block of `name=value` strings, each
    // ended by a 0, then a 0 that ends the block, sorted by name in any case.
    var commandLine = Array((["\"\(builtProduct("rayo").path)\""] + arguments).joined(separator: " ").utf16) + [0]
    let block = environment.sorted { $0.key.uppercased() < $1.key.uppercased() }
        .map { "\($0.key)=\($0.value)\0" }.joined() + "\0"

    // Start `rayo` on a new console, inheriting no handle of these tests.
    var startup = STARTUPINFOW()
    startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
    var started = PROCESS_INFORMATION()
    let didStart = block.withCString(encodedAs: UTF16.self) { block in
        directory.path.withCString(encodedAs: UTF16.self) { directory in
            CreateProcessW(nil, &commandLine, nil, nil, false, DWORD(CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT),
                           UnsafeMutableRawPointer(mutating: block), directory, &startup, &started)
        }
    }
    try #require(didStart, "rayo didn't start: Windows error \(GetLastError())")
    defer {
        CloseHandle(started.hThread)
        CloseHandle(started.hProcess)
    }

    // Wait for `rayo` to end, and give its exit code.
    WaitForSingleObject(started.hProcess, INFINITE)
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
#endif
