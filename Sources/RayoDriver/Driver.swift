import Foundation
import RayoIR
import RayoLLVM
import RayoSema
import RayoSyntax

public enum Driver {
    public struct Result: Equatable, Sendable {
        public var exitCode: Int32
        public var output: String
        public var errors: String

        public init(exitCode: Int32, output: String, errors: String) {
            self.exitCode = exitCode
            self.output = output
            self.errors = errors
        }
    }

    /// The exit code of a run whose program panics.
    public static let panicExitCode = LLVMEmitter.panicExitStatus

    static let usage = """
        usage: rayoc <command> <file>

        commands:
          parse    parse the file and print its syntax tree
          check    check the file and report its errors
          build    compile the file to an executable beside it, named without '.rayo'
          run      compile the file and run it

        """

    private enum Command: String {
        case parse, check, build, run
    }

    /// Where `rayoc run` sends what the program writes.
    public enum ProgramOutput: Sendable {
        /// Into the result, once the program ends.
        case captured
        /// To `rayoc`'s own standard output and error, as the program writes it.
        case inherited
    }

    /// Runs `rayoc` with `arguments`, which exclude the program's name, reading source files through
    /// `readFile`, which returns nil for a file it can't read.
    public static func run(_ arguments: [String], programOutput: ProgramOutput = .captured,
                           readFile: (String) -> String?) -> Result {
        guard arguments.count == 2, let command = Command(rawValue: arguments[0]) else {
            return Result(exitCode: 2, output: "", errors: usage)
        }
        let path = arguments[1]
        if command == .build {
            if !path.hasSuffix(".rayo") { return failure("'\(path)' doesn't end in '.rayo'") }
            if URL(fileURLWithPath: path).lastPathComponent == ".rayo" {
                return failure("'\(path)' has no name before '.rayo'")
            }
        }
        guard let source = readFile(path) else { return failure("can't read '\(path)'") }

        let (file, diagnostics) = Parser.parse(source)
        if !diagnostics.isEmpty { return failure(diagnostics, in: path) }
        if command == .parse { return Result(exitCode: 0, output: file.dump + "\n", errors: "") }

        let checked = Checker.check(file)
        guard let program = checked.program else { return failure(checked.diagnostics, in: path) }
        if command == .check { return Result(exitCode: 0, output: "", errors: "") }

        let llvmIR = LLVMEmitter.emit(Lowering.lower(program), sourcePath: path)
        do {
            if command == .build {
                try Toolchain.link(llvmIR, to: URL(fileURLWithPath: String(path.dropLast(".rayo".count))))
                return Result(exitCode: 0, output: "", errors: "")
            }
            return try compileAndRun(llvmIR, output: programOutput)
        } catch let toolchainFailure as Toolchain.Failure {
            return failure(toolchainFailure.message)
        } catch {
            return failure("\(error)")
        }
    }

    private static func failure(_ message: String) -> Result {
        Result(exitCode: 1, output: "", errors: "rayoc: \(message)\n")
    }

    private static func failure(_ diagnostics: [Diagnostic], in path: String) -> Result {
        Result(exitCode: 1, output: "", errors: diagnostics.map { "\(path):\($0)\n" }.joined())
    }

    private static func compileAndRun(_ llvmIR: String, output: ProgramOutput) throws -> Result {
        let directory = try Toolchain.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("program")
        try Toolchain.link(llvmIR, to: executable)
        switch output {
        case .captured: return try Toolchain.runCapturingOutput(executable)
        case .inherited: return Result(exitCode: try Toolchain.runAttached(executable), output: "", errors: "")
        }
    }
}
