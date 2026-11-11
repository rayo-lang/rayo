import Foundation

/// The driver, `rayo`, which has the compiler, `rayoc`, compile a source file, and links and runs the program.
public enum Driver {
    static let usage = """
        usage: rayo <command> <file>
               rayo build|run [--debug | --release] [--linker=lld | --linker=platform] <file>

        commands:
          check    check the file and report its errors
          build    compile the file to an executable beside it, named without '.rayo'
          run      compile the file and run it

        build modes:
          --debug    integer overflow panics, and the program isn't optimised
          --release  integer overflow wraps, and the program is optimised; a build that names no mode is a
                     release build

        linkers:
          --linker=lld       LLD, from the LLVM that rayo was built with; the linker when none is named
          --linker=platform  the platform's own linker

        """

    private enum Command: String {
        case check, build, run
    }

    /// What the arguments ask `rayo` to do.
    private struct Invocation {
        var command: Command
        var mode: BuildMode
        var linker: Linker
        var path: String

        init(_ arguments: [String]) throws(CommandLineError) {
            guard let command = arguments.first.flatMap(Command.init(rawValue:)) else { throw .usage }
            var operands = arguments.dropFirst()
            var mode: BuildMode?
            var linker: Linker?
            while command != .check, operands.count > 1, let option = operands.first {
                if let newMode = BuildMode(rawValue: option), mode == nil {
                    mode = newMode
                } else if let name = Self.value(of: option, named: "--linker"), linker == nil {
                    guard let newLinker = Linker(rawValue: name) else { throw .unknownLinker(name) }
                    linker = newLinker
                } else {
                    throw .usage
                }
                operands = operands.dropFirst()
            }
            guard operands.count == 1, let path = operands.first, !Self.isOption(path) else { throw .usage }
            self.command = command
            self.mode = mode ?? .release
            self.linker = linker ?? .lld
            self.path = path
        }

        /// Whether `operand` is one of `rayo`'s options, which leaves the arguments without a file.
        private static func isOption(_ operand: String) -> Bool {
            BuildMode(rawValue: operand) != nil || operand == "--linker" || value(of: operand, named: "--linker") != nil
        }

        /// The value `option` gives, when it is `name=value`.
        private static func value(of option: String, named name: String) -> String? {
            option.hasPrefix(name + "=") ? String(option.dropFirst(name.count + 1)) : nil
        }
    }

    /// Why the arguments don't make a command `rayo` can run.
    private enum CommandLineError: Error {
        case usage
        case unknownLinker(String)

        var errors: String {
            switch self {
            case .usage: Driver.usage
            case .unknownLinker(let name): "rayo: unknown linker '\(name)': use --linker=lld or --linker=platform\n"
            }
        }
    }

    /// Runs `rayo` with `arguments`, which exclude the program's name. It compiles with the `rayoc` at `compiler`,
    /// and `build` and `run` link with `linkTools`; `environment` is the environment those tools and a program run in.
    public static func run(
        _ arguments: [String], programOutput: ProgramOutput = .captured,
        environment: [String: String] = ProcessInfo.processInfo.environment, compiler: URL,
        linkTools: LinkTools = .installed,
    ) -> CommandResult {
        // Read what the arguments ask for.
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            // Arguments that ask for nothing `rayo` does are reported with how to use it.
            return CommandResult(exitCode: 2, output: "", errors: error.errors)
        }

        // Run the command the arguments ask for, with the host's tools.
        let toolchain = Toolchain(compiler: compiler, tools: linkTools, linker: invocation.linker,
                                  environment: environment)
        let command = CommandRun(invocation: invocation, toolchain: toolchain, programOutput: programOutput)
        do {
            return try command.result()
        } catch {
            // A command that stops is reported with why.
            return result(of: error)
        }
    }

    /// Returns the `rayoc` that `rayo` compiles with: the one `RAYOC` in `environment` names, or else the one
    /// beside `executable`, the `rayo` that runs.
    public static func compiler(in environment: [String: String], besides executable: URL) -> URL {
        // `RAYOC` names the compiler to use.
        if let path = environment["RAYOC"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return executable.deletingLastPathComponent().appendingPathComponent("rayoc")
    }

    /// The command an invocation asks for, run on the file it names, with the host's tools.
    private struct CommandRun {
        var invocation: Invocation
        var toolchain: Toolchain
        var programOutput: ProgramOutput

        func result() throws(CommandError) -> CommandResult {
            switch invocation.command {
            case .check: try check()
            case .build: try build()
            case .run: try runProgram()
            }
        }

        /// Checks the file, and writes nothing.
        private func check() throws(CommandError) -> CommandResult {
            try toolchain.compile(["--check", invocation.path])

            return CommandResult(exitCode: 0, output: "", errors: "")
        }

        /// Compiles the file to an executable beside it, and writes nothing else.
        private func build() throws(CommandError) -> CommandResult {
            // A path that names no executable stops `build` before it compiles the file.
            let executable = try executable(building: invocation.path)

            // Compile the file to object code, and link that into the executable.
            try Toolchain.withTemporaryDirectory { directory throws(CommandError) in
                let objectFile = try compile(into: directory)
                try toolchain.link(objectFile, to: executable)
            }

            return CommandResult(exitCode: 0, output: "", errors: "")
        }

        /// Compiles the file and runs it, and gives what the run gave.
        private func runProgram() throws(CommandError) -> CommandResult {
            try Toolchain.withTemporaryDirectory { directory throws(CommandError) in
                let objectFile = try compile(into: directory)
                return try toolchain.linkAndRun(objectFile, output: programOutput)
            }
        }

        /// Compiles the file to object code, in the invocation's build mode, and returns the object file, which it
        /// writes in `directory`.
        private func compile(into directory: URL) throws(CommandError) -> URL {
            let objectFile = directory.appendingPathComponent("program.o")
            try toolchain.compile([invocation.mode.rawValue, "-o", objectFile.path, invocation.path])
            return objectFile
        }

        /// Returns the executable for the source at `path`, which is the same path without `.rayo`, or fails when
        /// that names no file apart from the source.
        private func executable(building path: String) throws(CommandError) -> URL {
            // A path that doesn't end in '.rayo' would name the source itself.
            guard path.hasSuffix(".rayo") else { throw .failed("'\(path)' doesn't end in '.rayo'") }
            let name = URL(fileURLWithPath: path).lastPathComponent.dropLast(".rayo".count)
            // An empty name, '.' or '..' would name the source's own directory.
            guard !name.isEmpty && name != "." && name != ".." else {
                throw .failed("'\(path)' has no name before '.rayo'")
            }
            return URL(fileURLWithPath: String(path.dropLast(".rayo".count)))
        }
    }

    /// Returns what `rayo` gives when a command stops with `error`.
    private static func result(of error: CommandError) -> CommandResult {
        switch error {
        // A file `rayoc` didn't compile ends the command as `rayoc` ended, with its errors.
        case .compileFailed(let exitCode, let errors):
            CommandResult(exitCode: exitCode, output: "", errors: errors)
        // A reason of rayo's own is shown as its message.
        case .failed(let message):
            CommandResult(exitCode: 1, output: "", errors: "rayo: \(message)\n")
        }
    }
}
