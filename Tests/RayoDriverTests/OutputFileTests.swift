import Foundation
import Testing
import RayoDriver

struct OutputFileTests {
    @Test func `rayo runs in a directory whose earlier run's files are still open for writing`() throws {
        try withTemporaryDirectory { directory in
            // Run a program once in the directory.
            let answer = CommandResult(exitCode: 0, output: "42\n", errors: "")
            _ = try save("func main() { print(42) }", as: "main.rayo", in: directory)
            #expect(rayo(["run", "main.rayo"], in: directory) == answer)

            // Hold each file the run left open for writing, as a process that outlives the run might.
            let leftFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != "main.rayo" }
            let openHandles = try leftFiles.map { try FileHandle(forWritingTo: $0) }
            defer { for handle in openHandles { try? handle.close() } }

            #expect(rayo(["run", "main.rayo"], in: directory) == answer)
        }
    }
}
