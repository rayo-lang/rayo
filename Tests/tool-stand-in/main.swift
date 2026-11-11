import Foundation
import ToolStandIn

// The file this run was started as names the stand-in installed there.
let path = CommandLine.arguments[0]
do {
    try ToolStandIn.installed(at: path).run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    // Without a stand-in to act as, the run can't stand in for anything.
    FileHandle.standardError.write(Data("tool-stand-in: no stand-in installed at '\(path)': \(error)\n".utf8))
    exit(127)
}
