#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import RayoDriver

/// Reads the file at `path`, and returns its bytes, or nil when it can't be opened or read.
func readFile(_ path: String) -> [UInt8]? {
    // A file that can't be opened can't be read.
    guard let handle = fopen(path, "rb") else { return nil }
    defer { fclose(handle) }

    // Read the file a buffer at a time, to its end or the first error.
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&buffer, 1, buffer.count, handle)
        bytes.append(contentsOf: buffer[0..<count])
        // A short read ends the file, whether at its end or at an error.
        if count < buffer.count { break }
    }

    // A read that ended at an error returns nothing of what it read.
    guard ferror(handle) == 0 else { return nil }
    return bytes
}

/// Writes all of `text` to `descriptor`, retrying after a partial or interrupted write.
func writeAll(_ text: String, to descriptor: Int32) {
    var bytes = Array(text.utf8)[...]
    while !bytes.isEmpty {
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        // A write that a signal interrupted before it wrote anything is tried again.
        if written < 0 && errno == EINTR { continue }
        // Any other failed write gives up on what is left.
        if written <= 0 { return }
        bytes = bytes.dropFirst(written)
    }
}

let result = Driver.run(Array(CommandLine.arguments.dropFirst()), programOutput: .inherited, readFile: readFile)
writeAll(result.output, to: STDOUT_FILENO)
writeAll(result.errors, to: STDERR_FILENO)
exit(result.exitCode)
