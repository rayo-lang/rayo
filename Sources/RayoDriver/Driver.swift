import Foundation
import RayoDiagnostics
import RayoIR
import RayoLLVM
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
    public static let panicExitCode = LLVMEmitter.panicExitCode

    static let usage = """
        usage: rayoc <command> <file>
               rayoc build|run [--debug | --release] <file>

        commands:
          check    check the file and report its errors
          build    compile the file to an executable beside it, named without '.rayo'
          run      compile the file and run it

        build modes:
          --debug    integer overflow panics
          --release  integer overflow wraps; a build that names no mode is a release build

        """

    private enum Command: String {
        case check, build, run
    }

    /// A build's mode, which turns the diagnostic checks on in a debug build and off in a release one.
    private enum BuildMode: String {
        case debug = "--debug"
        case release = "--release"
    }

    /// What the arguments ask `rayoc` to do.
    private struct Invocation {
        var command: Command
        var mode = BuildMode.release
        var path: String

        /// Nil when `arguments` don't fit the usage.
        init?(_ arguments: [String]) {
            guard let command = arguments.first.flatMap(Command.init(rawValue:)) else { return nil }
            var operands = arguments.dropFirst()
            if command == .build || command == .run, let mode = operands.first.flatMap(BuildMode.init(rawValue:)) {
                self.mode = mode
                operands = operands.dropFirst()
            }
            guard operands.count == 1, let path = operands.first else { return nil }
            self.command = command
            self.path = path
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
    /// `readFile`, which returns nil for a file it can't read. `environment` holds the search path for
    /// `clang`, and is the environment a program runs in.
    public static func run(_ arguments: [String], programOutput: ProgramOutput = .captured,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           readFile: (String) -> [UInt8]?) -> Result {
        guard let invocation = Invocation(arguments) else { return Result(exitCode: 2, output: "", errors: usage) }
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

            let llvmIR = LLVMEmitter.emit(Lowering.lower(program), sourcePath: path,
                                          checksOverflow: invocation.mode == .debug)
            let toolchain = Toolchain(environment: environment)
            if let executable {
                try toolchain.link(llvmIR, to: executable)
                return Result(exitCode: 0, output: "", errors: "")
            }
            return try toolchain.compileAndRun(llvmIR, output: programOutput)
        } catch let failure as Failure {
            return Self.failure(failure.message)
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
