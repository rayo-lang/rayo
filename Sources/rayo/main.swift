import Foundation
import RayoDriver

// The `rayo` that runs is the file the system started, not a link to it, so `rayoc` is found beside that file.
let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let environment = ProcessInfo.processInfo.environment
let result = Driver.run(Array(CommandLine.arguments.dropFirst()),
                        compiler: Driver.compiler(in: environment, beside: executable), processOutput: .inherited,
                        environment: environment)

// What can't be written has nowhere else to go, so a failed write leaves only the exit code.
try? FileHandle.standardOutput.write(contentsOf: Data(result.output.utf8))
try? FileHandle.standardError.write(contentsOf: Data(result.errors.utf8))
exit(result.exitCode)
