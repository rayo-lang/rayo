#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import RayoCompiler

func readFile(_ path: String) -> [UInt8]? {
    guard let handle = fopen(path, "rb") else { return nil }
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
    guard let handle = fopen(path, "wb") else { return false }
    let written = bytes.withUnsafeBytes { fwrite($0.baseAddress, 1, $0.count, handle) }
    // A write that stops short, or a close that fails to flush, leaves the file incomplete.
    return fclose(handle) == 0 && written == bytes.count
}

/// Writes all of `text` to `descriptor`, retrying after a partial or interrupted write.
func writeAll(_ text: String, to descriptor: Int32) {
    var bytes = Array(text.utf8)[...]
    while !bytes.isEmpty {
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        if written < 0 && errno == EINTR { continue }
        if written <= 0 { return }
        bytes = bytes.dropFirst(written)
    }
}

let result = Compiler.run(Array(CommandLine.arguments.dropFirst()), readFile: readFile, writeFile: writeFile)
writeAll(result.errors, to: STDERR_FILENO)
exit(result.exitCode)
