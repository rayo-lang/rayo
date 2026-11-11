#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import RayoDriver

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

// The `rayo` that runs is the file the system started, not a link to it, so `rayoc` is found beside that file.
let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let environment = ProcessInfo.processInfo.environment
let result = Driver.run(Array(CommandLine.arguments.dropFirst()),
                        compiler: Driver.compiler(in: environment, beside: executable), processOutput: .inherited,
                        environment: environment)
writeAll(result.output, to: STDOUT_FILENO)
writeAll(result.errors, to: STDERR_FILENO)
exit(result.exitCode)
