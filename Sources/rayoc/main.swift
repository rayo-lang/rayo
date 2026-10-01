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

let result = Driver.run(Array(CommandLine.arguments.dropFirst()), readFile: readFile)
fputs(result.output, stdout)
fputs(result.errors, stderr)
exit(result.exitCode)
