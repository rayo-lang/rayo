import Foundation

/// What the `tool-stand-in` executable does when a test has it stand in for a tool `rayo` runs, such as clang, a
/// linker or `rayoc`: a few steps, then an end.
public struct ToolStandIn: Codable, Equatable, Sendable {
    /// A thing the stand-in does before it ends.
    public enum Step: Codable, Equatable, Sendable {
        /// Writes the text to standard error.
        case write(String)
        /// Makes an empty file at the path.
        case touch(String)
        /// Fails, writing why, when one of the stand-in's arguments ends in one of the suffixes.
        case refuseArguments(endingIn: [String])
    }

    /// How the stand-in ends, once its steps are done.
    public enum End: Codable, Equatable, Sendable {
        /// Exits with the code.
        case exit(Int32)
        /// Runs the tool at the path with the stand-in's own arguments, and exits as that tool exits.
        case handOff(toToolAt: String)
        /// Ends by the signal.
        case signal(Int32)
    }

    public var steps: [Step]
    public var end: End

    public init(_ steps: [Step] = [], then end: End) {
        self.steps = steps
        self.end = end
    }

    /// Makes the file at `url` run the `tool-stand-in` executable at `executable` as this stand-in.
    public func install(at url: URL, running executable: URL) throws {
        // A link, unlike a copy, is never a file open for writing that a process started meanwhile could hold
        // open, which would keep it from running.
        try JSONEncoder().encode(self).write(to: Self.descriptionFile(of: url.path))
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: executable)
    }

    /// The stand-in installed at `path`, the file a run of `tool-stand-in` was started as.
    public static func installed(at path: String) throws -> ToolStandIn {
        try JSONDecoder().decode(ToolStandIn.self, from: Data(contentsOf: descriptionFile(of: path)))
    }

    /// Does the steps with `arguments`, the arguments the stand-in was run with, and ends as `end` says.
    public func run(arguments: [String]) -> Never {
        for step in steps {
            switch step {
            // The text goes out at once, before anything that follows it.
            case .write(let text):
                FileHandle.standardError.write(Data(text.utf8))
            // The file shows that the stand-in ran.
            case .touch(let path):
                FileManager.default.createFile(atPath: path, contents: nil)
            // An argument the tool wasn't meant to be given fails the run, and says which.
            case .refuseArguments(let suffixes):
                if let refused = arguments.first(where: { argument in suffixes.contains { argument.hasSuffix($0) } }) {
                    FileHandle.standardError.write(Data("tool-stand-in: given '\(refused)'\n".utf8))
                    Foundation.exit(1)
                }
            }
        }
        return finish(arguments: arguments)
    }

    /// Ends the stand-in as `end` says, handing `arguments` on to a tool that `end` names.
    private func finish(arguments: [String]) -> Never {
        switch end {
        // The code is the stand-in's own.
        case .exit(let code):
            Foundation.exit(code)
        // The tool runs on the stand-in's own standard input, output and error.
        case .handOff(let path):
            let tool = Process()
            tool.executableURL = URL(fileURLWithPath: path)
            tool.arguments = arguments
            do {
                try tool.run()
            } catch {
                // A tool that can't start ends the stand-in as a shell ends a command it can't run.
                FileHandle.standardError.write(Data("tool-stand-in: can't run '\(path)': \(error)\n".utf8))
                Foundation.exit(127)
            }
            tool.waitUntilExit()
            Foundation.exit(tool.terminationStatus)
        // The signal ends the process before `raise` returns; the exit is for a signal it handles.
        case .signal(let signal):
            raise(signal)
            Foundation.exit(128 + signal)
        }
    }

    /// The file that describes the stand-in installed at `path`.
    private static func descriptionFile(of path: String) -> URL {
        URL(fileURLWithPath: path + ".stand-in.json")
    }
}
