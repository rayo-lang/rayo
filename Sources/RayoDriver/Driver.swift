import Foundation
import RayoLLVMInstall

/// The driver, `rayo`, which has the compiler, `rayoc`, compile a source file, and links and runs the program.
public enum Driver {
    static let usage = """
        usage: rayo <command> <file>
               rayo build|run [--debug | --release] [--linker=lld | --linker=platform] <file>

        commands:
          check    check the file and report its errors
          build    compile the file to an executable beside it, named after it
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
            // Arguments that start with no command `rayo` knows ask for nothing it does.
            guard let command = arguments.first.flatMap(Command.init(rawValue:)) else { throw .usage }

            // Read each option of `build` and `run` before the file, each at most once; `check` takes none.
            var operands = arguments.dropFirst()
            var mode: BuildMode?
            var linker: Linker?
            while command != .check, operands.count > 1, let option = operands.first {
                if let newMode = BuildMode(rawValue: option), mode == nil {
                    // A build mode says how the program is built.
                    mode = newMode
                } else if let name = Self.value(of: option, named: "--linker"), linker == nil {
                    // `--linker=` names the linker, which has to be one `rayo` knows.
                    guard let newLinker = Linker(rawValue: name) else { throw .unknownLinker(name) }
                    linker = newLinker
                } else {
                    // An option `rayo` doesn't take, or one given twice, asks for nothing it does.
                    throw .usage
                }
                operands = operands.dropFirst()
            }

            // The one operand left is the source file; an option there leaves the arguments without one.
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
        _ arguments: [String], compiler: URL, processOutput: ProcessOutput = .captured,
        environment: [String: String] = ProcessInfo.processInfo.environment, linkTools: LinkTools = .installed,
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
                                  output: processOutput, environment: environment)
        let command = CommandRun(invocation: invocation, toolchain: toolchain)
        do {
            return try command.result()
        } catch {
            // A command that stops is reported with why.
            return result(of: error)
        }
    }

    /// Returns the `rayoc` that `rayo` compiles with: the one `RAYOC` in `environment` names, or else the one
    /// beside `executable`, the `rayo` that runs.
    public static func compiler(in environment: [String: String], beside executable: URL) -> URL {
        // `RAYOC` names the compiler to use.
        if let path = environment["RAYOC"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return executable.deletingLastPathComponent().appendingPathComponent(Executable.fileName("rayoc"))
    }

    /// The command an invocation asks for, run on the file it names, with the host's tools.
    private struct CommandRun {
        var invocation: Invocation
        var toolchain: Toolchain

        func result() throws(CommandError) -> CommandResult {
            switch invocation.command {
            case .check: try check()
            case .build: try build()
            case .run: try runProgram()
            }
        }

        /// Checks the file, and writes nothing but what `rayoc` wrote.
        private func check() throws(CommandError) -> CommandResult {
            let errors = try toolchain.check(invocation.path)

            return CommandResult(exitCode: 0, output: "", errors: errors)
        }

        /// Compiles the file to an executable beside it, and writes nothing but what `rayoc` wrote.
        private func build() throws(CommandError) -> CommandResult {
            let executable = try executable(building: invocation.path)

            let compiled = try toolchain.compile(invocation.path, mode: invocation.mode) {
                objectFile throws(CommandError) in try toolchain.link(objectFile, to: executable)
            }

            return CommandResult(exitCode: 0, output: "", errors: compiled.errors)
        }

        /// Compiles the file and runs it, and gives what the run gave, after what `rayoc` wrote.
        private func runProgram() throws(CommandError) -> CommandResult {
            let compiled = try toolchain.compile(invocation.path, mode: invocation.mode) {
                objectFile throws(CommandError) in try toolchain.linkAndRun(objectFile)
            }

            return CommandResult(exitCode: compiled.value.exitCode, output: compiled.value.output,
                                 errors: compiled.errors + compiled.value.errors)
        }

        /// Returns the executable for the source at `path`: the same path without `.rayo`, and on Windows with
        /// `.exe`. Fails when `path` doesn't end in `.rayo`, or has no name before it.
        private func executable(building path: String) throws(CommandError) -> URL {
            // A path that doesn't end in '.rayo' isn't a source's, and where executables take no extension it would
            // name the source itself.
            guard path.hasSuffix(".rayo") else { throw .failed("'\(path)' doesn't end in '.rayo'") }
            let name = URL(fileURLWithPath: path).lastPathComponent.dropLast(".rayo".count)
            // An empty name, '.' or '..' names no program, and where executables take no extension it would name the
            // source's own directory.
            guard !name.isEmpty && name != "." && name != ".." else {
                throw .failed("'\(path)' has no name before '.rayo'")
            }
            return URL(fileURLWithPath: Executable.fileName(String(path.dropLast(".rayo".count))))
        }
    }

    /// Returns what `rayo` gives when a command stops with `error`.
    private static func result(of error: CommandError) -> CommandResult {
        switch error {
        // A file `rayoc` didn't compile ends the command as `rayoc` ended, with its errors.
        case .compileFailed(let exitCode, let errors):
            CommandResult(exitCode: exitCode, output: "", errors: errors)
        // A reason of rayo's own is shown as its message, after what `rayoc` wrote.
        case .failed(let message, let errors):
            CommandResult(exitCode: 1, output: "", errors: errors + "rayo: \(message)\n")
        }
    }
}
