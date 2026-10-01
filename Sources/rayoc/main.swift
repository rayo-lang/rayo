#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import RayoDriver

func readFile(_ path: String) -> String? {
    guard let handle = fopen(path, "rb") else { return nil }
    defer { fclose(handle) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&buffer, 1, buffer.count, handle)
        bytes.append(contentsOf: buffer[0..<count])
        if count < buffer.count { break }
    }
    if ferror(handle) != 0 { return nil }
    return String(decoding: bytes, as: UTF8.self)
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

let result = Driver.run(Array(CommandLine.arguments.dropFirst()), readFile: readFile)
writeAll(result.output, to: STDOUT_FILENO)
writeAll(result.errors, to: STDERR_FILENO)
exit(result.exitCode)
