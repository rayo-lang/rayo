import Foundation
import ToolStandIn
#if os(Windows)
import WinSDK
#endif

#if os(Windows)
// clang runs a tool it finds in a directory -B names by a path without `.exe`, so the path a run was started as can
// lack it; Windows names the file the process runs, which is the stand-in's copy.
var buffer = [UInt16](repeating: 0, count: 32_768)
let length = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
let path = String(decoding: buffer[..<length], as: UTF16.self)
#else
// The file this run was started as is the link that names the stand-in installed there.
let path = CommandLine.arguments[0]
#endif

do {
    try ToolStandIn.installed(at: path).run(as: path, arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    // Without a stand-in to act as, the run can't stand in for anything.
    FileHandle.standardError.write(Data("tool-stand-in: no stand-in installed at '\(path)': \(error)\n".utf8))
    exit(127)
}
