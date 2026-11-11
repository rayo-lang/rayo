import Foundation
import RayoDiagnostics
import RayoIR
import RayoRuntime

public enum Driver {
    public struct Result: Equatable, Sendable {
        public var exitCode: Int32
        public var output: String
        public var errors: String
        /// The errors found in the program, which `errors` also shows.
        public var diagnostics: [Diagnostic]

        public init(exitCode: Int32, output: String, errors: String, diagnostics: [Diagnostic] = []) {
            self.exitCode = exitCode
            self.output = output
            self.errors = errors
            self.diagnostics = diagnostics
        }
    }

    /// The exit code of a run whose program panics.
    public static let panicExitCode = ProgramRuntime.panicExitCode

    static let usage = """
        usage: rayoc <command> <file>
               rayoc build|run [--debug | --release] [--linker=lld | --linker=platform] <file>

        commands:
          check    check the file and report its errors
          build    compile the file to an executable beside it, named without '.rayo'
          run      compile the file and run it

        build modes:
          --debug    integer overflow panics, and the program isn't optimised
          --release  integer overflow wraps, and the program is optimised; a build that names no mode is a
                     release build

        linkers:
          --linker=lld       LLD, from the LLVM that rayoc was built with; the linker when none is named
          --linker=platform  the platform's own linker

        """

    private enum Command: String {
        case check, build, run
    }

    /// What the arguments ask `rayoc` to do.
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

        /// Whether `operand` is one of `rayoc`'s options, which leaves the arguments without a file.
        private static func isOption(_ operand: String) -> Bool {
            BuildMode(rawValue: operand) != nil || operand == "--linker" || value(of: operand, named: "--linker") != nil
        }

        /// The value `option` gives, when it is `name=value`.
        private static func value(of option: String, named name: String) -> String? {
            option.hasPrefix(name + "=") ? String(option.dropFirst(name.count + 1)) : nil
        }
    }

    /// Why the arguments don't make a command `rayoc` can run.
    private enum CommandLineError: Error {
        case usage
        case unknownLinker(String)

        var errors: String {
            switch self {
            case .usage: Driver.usage
            case .unknownLinker(let name): "rayoc: unknown linker '\(name)': use --linker=lld or --linker=platform\n"
            }
        }
    }

    /// Runs `rayoc` with `arguments`, which exclude the program's name, reading source files through
    /// `readFile`, which returns nil for a file it can't read. `build` and `run` link with `linkTools`, and
    /// `environment` is the environment that clang and a program run in.
    public static func run(_ arguments: [String], programOutput: ProgramOutput = .captured,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           linkTools: LinkTools = .installed, readFile: @escaping (String) -> [UInt8]?) -> Result {
        // Read what the arguments ask for.
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            // Arguments that ask for nothing `rayoc` does are reported with how to use it.
            return Result(exitCode: 2, output: "", errors: error.errors)
        }

        // Run the command the arguments ask for, with the host's tools.
        let toolchain = Toolchain(tools: linkTools, linker: invocation.linker, environment: environment)
        let command = CommandRun(invocation: invocation, readFile: readFile, toolchain: toolchain,
                                 programOutput: programOutput)
        do {
            return try command.result()
        } catch {
            // A command that stops is reported with why.
            return result(of: error, in: invocation.path)
        }
    }

    /// The command an invocation asks for, run on the file it names, with the host's files and tools.
    private struct CommandRun {
        var invocation: Invocation
        var readFile: (String) -> [UInt8]?
        var toolchain: Toolchain
        var programOutput: ProgramOutput

        func result() throws(CompilationError) -> Result {
            switch invocation.command {
            case .check: try check()
            case .build: try build()
            case .run: try runProgram()
            }
        }

        /// Checks the file, and writes nothing.
        private func check() throws(CompilationError) -> Result {
            _ = try compile.run(invocation.path)

            return Result(exitCode: 0, output: "", errors: "")
        }

        /// Compiles the file to an executable beside it, and writes nothing else.
        private func build() throws(CompilationError) -> Result {
            // A path that names no executable stops `build` before it reads the file.
            let executable = try executable(building: invocation.path)

            // Compile the file, and link it into the executable.
            try pipeline {
                objectCode
                Link(toolchain: toolchain, executable: executable)
            }.run(invocation.path)

            return Result(exitCode: 0, output: "", errors: "")
        }

        /// Compiles the file and runs it, and gives what the run gave.
        private func runProgram() throws(CompilationError) -> Result {
            try pipeline {
                objectCode
                LinkAndRun(toolchain: toolchain, output: programOutput)
            }.run(invocation.path)
        }

        /// Compiles the source file at a path to Rayo IR.
        private var compile: some CompilationStep<String, IRProgram> {
            pipeline {
                ReadSource(readFile: readFile)
                Parse()
                Check()
                Lower()
                CheckOwnership()
            }
        }

        /// Compiles the source file at a path to object code, as a build in the invocation's mode.
        private var objectCode: some CompilationStep<String, [UInt8]> {
            pipeline {
                compile
                Emit(mode: invocation.mode, sourcePath: invocation.path)
            }
        }

        /// Returns the executable for the source at `path`, which is the same path without `.rayo`, or fails when
        /// that names no file apart from the source.
        private func executable(building path: String) throws(CompilationError) -> URL {
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

    /// What `rayoc` gives when a compile of the file at `path` stops with `error`.
    private static func result(of error: CompilationError, in path: String) -> Result {
        switch error {
        // Each of the program's errors is shown at its place in the file.
        case .rejected(let diagnostics):
            Result(exitCode: 1, output: "", errors: diagnostics.map { "\(path):\($0)\n" }.joined(),
                   diagnostics: diagnostics)
        // A reason of rayoc's own is shown as its message.
        case .failed(let message):
            Result(exitCode: 1, output: "", errors: "rayoc: \(message)\n")
        }
    }
}
