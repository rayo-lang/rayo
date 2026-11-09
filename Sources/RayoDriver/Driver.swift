import Foundation
import RayoDiagnostics
import RayoIR
import RayoLLVM
import RayoRuntime
import RayoSema
import RayoSyntax

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

    /// A build's mode, which turns the diagnostic checks on and optimisation off in a debug build, and the other way
    /// round in a release one.
    private enum BuildMode: String {
        case debug = "--debug"
        case release = "--release"
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
            guard operands.count == 1, let path = operands.first else { throw .usage }
            self.command = command
            self.mode = mode ?? .release
            self.linker = linker ?? .lld
            self.path = path
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
            case .usage: return Driver.usage
            case .unknownLinker(let name): return "rayoc: unknown linker '\(name)': use --linker=lld or --linker=platform\n"
            }
        }
    }

    /// Where `rayoc run` sends what the program writes.
    public enum ProgramOutput: Sendable {
        /// Into the result, once the program ends.
        case captured
        /// To `rayoc`'s own standard output and error, as the program writes it.
        case inherited
    }

    /// Runs `rayoc` with `arguments`, which exclude the program's name, reading source files through
    /// `readFile`, which returns nil for a file it can't read. `build` and `run` link with `linkTools`, and
    /// `environment` is the environment that clang and a program run in.
    public static func run(_ arguments: [String], programOutput: ProgramOutput = .captured,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           linkTools: LinkTools = .installed, readFile: (String) -> [UInt8]?) -> Result {
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            return Result(exitCode: 2, output: "", errors: error.errors)
        }
        let command = invocation.command
        let path = invocation.path
        do {
            let executable = command == .build ? try executable(building: path) : nil
            guard let source = readFile(path) else { throw Failure("can't read '\(path)'") }

            let (file, diagnostics) = Parser.parse(source)
            if !diagnostics.isEmpty { return failure(diagnostics, in: path) }

            let checked = Checker.check(file)
            guard let program = checked.program else { return failure(checked.diagnostics, in: path) }
            if command == .check { return Result(exitCode: 0, output: "", errors: "") }

            let objectCode = try LLVMEmitter.objectCode(for: Lowering.lower(program), sourcePath: path,
                                                        checksOverflow: invocation.mode == .debug,
                                                        optimizes: invocation.mode == .release)
            let toolchain = Toolchain(tools: linkTools, linker: invocation.linker, environment: environment)
            if let executable {
                try toolchain.link(objectCode, to: executable)
                return Result(exitCode: 0, output: "", errors: "")
            }
            return try toolchain.linkAndRun(objectCode, output: programOutput)
        } catch let failure as Failure {
            return Self.failure(failure.message)
        } catch let error as LLVMError {
            return failure("internal error: \(error.message)")
        } catch {
            return failure(error.localizedDescription)
        }
    }

    /// The executable that `build` writes for the source at `path`: the same path without `.rayo`.
    private static func executable(building path: String) throws(Failure) -> URL {
        guard path.hasSuffix(".rayo") else { throw Failure("'\(path)' doesn't end in '.rayo'") }
        let name = URL(fileURLWithPath: path).lastPathComponent.dropLast(".rayo".count)
        // An empty name, '.' or '..' would name the source's own directory.
        guard !name.isEmpty && name != "." && name != ".." else {
            throw Failure("'\(path)' has no name before '.rayo'")
        }
        return URL(fileURLWithPath: String(path.dropLast(".rayo".count)))
    }

    private static func failure(_ message: String) -> Result {
        Result(exitCode: 1, output: "", errors: "rayoc: \(message)\n")
    }

    private static func failure(_ diagnostics: [Diagnostic], in path: String) -> Result {
        Result(exitCode: 1, output: "", errors: diagnostics.map { "\(path):\($0)\n" }.joined(), diagnostics: diagnostics)
    }
}

/// A reason `rayoc` stops, which it reports as an error of its own.
struct Failure: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}
