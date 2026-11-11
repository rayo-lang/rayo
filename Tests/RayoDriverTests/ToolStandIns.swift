import Foundation
import ToolStandIn

/// Installs `standIn` as the tool `name` in `directory`, run by the built `tool-stand-in`, and returns the tool.
func install(_ standIn: ToolStandIn, as name: String, in directory: URL) throws -> URL {
    let tool = directory.appendingPathComponent(name)
    try standIn.install(at: tool, running: builtProduct("tool-stand-in"))
    return tool
}
