#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(CRT)
import CRT
#endif
import RayoCompiler

/// The C library's descriptors for standard output and standard error.
#if os(Windows)
// The Windows C runtime numbers its standard descriptors as POSIX does.
let standardOutput: Int32 = 1
let standardError: Int32 = 2
#else
let standardOutput = STDOUT_FILENO
let standardError = STDERR_FILENO
#endif

func readFile(_ path: String) -> [UInt8]? {
    guard let handle = openFile(path, mode: "rb") else { return nil }
    defer { fclose(handle) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&buffer, 1, buffer.count, handle)
        bytes.append(contentsOf: buffer[0..<count])
        if count < buffer.count { break }
    }
    return ferror(handle) != 0 ? nil : bytes
}

/// Writes `bytes` to the file at `path`, replacing what it held, and returns whether all of them were written.
func writeFile(_ path: String, _ bytes: [UInt8]) -> Bool {
    guard let handle = openFile(path, mode: "wb") else { return false }
    let written = bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, handle) }
    // A write that stops short, or a close that fails to flush, leaves the file incomplete.
    return fclose(handle) == 0 && written == bytes.count
}

/// Opens the file at `path` as `fopen` does with `mode`, or returns nil where it can't.
func openFile(_ path: String, mode: String) -> UnsafeMutablePointer<FILE>? {
    #if os(Windows)
    // `fopen` reads a path in the system's code page, which can't hold every name; `_wfsopen` reads UTF-16. It
    // shares the file as `fopen` does, where `_wfopen_s` would keep every other process from opening it meanwhile.
    path.withCString(encodedAs: UTF16.self) { path in
        mode.withCString(encodedAs: UTF16.self) { mode in _wfsopen(path, mode, _SH_DENYNO) }
    }
    #else
    fopen(path, mode)
    #endif
}

/// Writes all of `text` to `descriptor`, retrying after a partial or interrupted write.
func writeAll(_ text: String, to descriptor: Int32) {
    var bytes = Array(text.utf8)[...]
    while !bytes.isEmpty {
        let written = bytes.withUnsafeBytes { writeSome(to: descriptor, $0) }
        if written < 0 && errno == EINTR { continue }
        if written <= 0 { return }
        bytes = bytes.dropFirst(written)
    }
}

/// Writes what it can of `bytes` to `descriptor`, and returns how many it wrote, or -1 when the write fails.
func writeSome(to descriptor: Int32, _ bytes: UnsafeRawBufferPointer) -> Int {
    #if os(Windows)
    // The Windows C runtime's `_write` takes the count as an `unsigned int`, and returns an `int`.
    Int(_write(descriptor, bytes.baseAddress, UInt32(bytes.count)))
    #else
    write(descriptor, bytes.baseAddress, bytes.count)
    #endif
}

#if os(Windows)
// The Windows C runtime writes a newline to a descriptor in text mode as "\r\n"; binary mode writes it as itself.
_ = _setmode(standardOutput, _O_BINARY)
_ = _setmode(standardError, _O_BINARY)
#endif

let result = Compiler.run(Array(CommandLine.arguments.dropFirst()), readFile: readFile, writeFile: writeFile)
writeAll(result.standardOutput, to: standardOutput)
writeAll(result.errors, to: standardError)
exit(result.exitCode)
