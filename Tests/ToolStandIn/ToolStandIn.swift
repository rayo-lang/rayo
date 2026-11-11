import Foundation

/// What the `tool-stand-in` executable does when a test has it stand in for a tool `rayo` runs, such as clang, a
/// linker or `rayoc`: a few steps, then an end.
public struct ToolStandIn: Codable {
    /// A thing the stand-in does before it ends.
    public enum Step: Codable {
        /// Writes the text to standard error.
        case write(String)
        /// Makes an empty file at the URL.
        case touch(URL)
        /// Fails, writing why, when one of the stand-in's arguments ends in one of the suffixes.
        case refuseArguments(endingIn: [String])
    }

    /// How the stand-in ends, once its steps are done.
    public enum End: Codable {
        /// Exits with the code.
        case exit(Int32)
        /// Runs the tool at the URL with the stand-in's own arguments, and ends as that tool ends.
        case handOff(toToolAt: URL)
        /// Ends by the signal.
        case signal(Int32)
    }

    public let steps: [Step]
    public let end: End

    public init(_ steps: [Step], then end: End) {
        self.steps = steps
        self.end = end
    }

    /// Makes the file at `url` run the `tool-stand-in` executable at `executable` as this stand-in.
    public func install(at url: URL, running executable: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.descriptionFile(of: url.path))

        // A link, unlike a copy, is never a file open for writing that a process started meanwhile could hold
        // open, which would keep it from running.
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: executable)
    }

    /// Reads the stand-in installed at `path`.
    public static func installed(at path: String) throws -> ToolStandIn {
        try JSONDecoder().decode(ToolStandIn.self, from: Data(contentsOf: descriptionFile(of: path)))
    }

    /// Does the steps, as the stand-in installed at `path`, with `arguments`, the arguments it was run with, and
    /// ends as `end` says.
    public func run(as path: String, arguments: [String]) -> Never {
        // Do each step in order; a refused argument ends the run there.
        for step in steps {
            switch step {
            // The text goes out at once, before anything that follows it.
            case .write(let text):
                FileHandle.standardError.write(Data(text.utf8))
            // The file shows that the stand-in ran.
            case .touch(let url):
                FileManager.default.createFile(atPath: url.path, contents: nil)
            // An argument the tool wasn't meant to be given fails the run, and says which.
            case .refuseArguments(let suffixes):
                if let refused = Self.firstArgument(of: arguments, endingIn: suffixes) {
                    FileHandle.standardError.write(Data("\(path): given '\(refused)'\n".utf8))
                    Foundation.exit(1)
                }
            }
        }

        finish(as: path, arguments: arguments)
    }

    /// Ends the stand-in installed at `path` as `end` says, handing `arguments` on to a tool that `end` names.
    private func finish(as path: String, arguments: [String]) -> Never {
        switch end {
        // The code is the stand-in's own.
        case .exit(let code):
            Foundation.exit(code)
        // The tool runs on the stand-in's own standard input, output and error.
        case .handOff(let tool):
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            do {
                try process.run()
            } catch {
                // A tool that can't start ends the stand-in as a shell ends a command it can't run.
                FileHandle.standardError.write(Data("\(path): can't run '\(tool.path)': \(error)\n".utf8))
                Foundation.exit(127)
            }
            process.waitUntilExit()
            // A tool that a signal ended ends the stand-in by the same signal, as if the tool had run in its place.
            if process.terminationReason == .uncaughtSignal { Self.end(by: process.terminationStatus) }
            Foundation.exit(process.terminationStatus)
        // The signal is the stand-in's own.
        case .signal(let signal):
            Self.end(by: signal)
        }
    }

    /// Ends the process by `signal`; a signal that the process handles, and so doesn't end it, ends it with 128 plus
    /// the signal, as a shell reports one that did.
    private static func end(by signal: Int32) -> Never {
        raise(signal)
        Foundation.exit(128 + signal)
    }

    /// The first of `arguments` that ends in one of `suffixes`, or nil where none does.
    private static func firstArgument(of arguments: [String], endingIn suffixes: [String]) -> String? {
        arguments.first { argument in suffixes.contains { argument.hasSuffix($0) } }
    }

    /// The file that describes the stand-in installed at `path`.
    private static func descriptionFile(of path: String) -> URL {
        URL(fileURLWithPath: path + ".stand-in.json")
    }
}
