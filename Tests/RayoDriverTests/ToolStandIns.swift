import Foundation
import RayoLLVMInstall
import ToolStandIn

/// Installs `standIn` as the executable `name` in `directory`, run by the built `tool-stand-in`, and returns the
/// executable.
func install(_ standIn: ToolStandIn, as name: String, in directory: URL) throws -> URL {
    let tool = directory.appendingPathComponent(Executable.fileName(name))
    try standIn.install(at: tool, running: builtProduct("tool-stand-in"))
    return tool
}
