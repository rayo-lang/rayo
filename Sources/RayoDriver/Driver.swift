import Foundation
import RayoDiagnostics
import RayoIR
import RayoLLVM
import RayoOwnership
import RayoRuntime
import RayoSema
import RayoSyntax

/// The `rayoc` command line, which checks, builds or runs a Rayo source file.
public enum Driver {
    /// The exit code of a run whose program panics.
    public static let panicExitCode = ProgramRuntime.panicExitCode

    /// Runs `rayoc` with `arguments`, which exclude the program's name, reading source files through
    /// `readFile`, which returns nil for a file it can't read. `build` and `run` link with `linkTools`, and
    /// `environment` is the environment that clang and a program run in.
    public static func run(_ arguments: [String], programOutput: ProgramOutput = .captured,
                           environment: [String: String] = ProcessInfo.processInfo.environment,
                           linkTools: LinkTools = .installed, readFile: (String) -> [UInt8]?) -> RunResult {
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            // Arguments that make no command `rayoc` can run exit with 2, where every other error exits with 1.
            return RunResult(exitCode: 2, output: "", errors: error.errors)
        }

        // Carry out the command with the tools and environment given.
        let processes = ProcessRunner(environment: environment)
        let toolchain = Toolchain(tools: linkTools, linker: invocation.linker, processes: processes)
        do {
            return try perform(invocation, toolchain: toolchain, programOutput: programOutput, readFile: readFile)
        } catch {
            // Anything that stops the work is `rayoc`'s own error.
            return failure(reporting: error)
        }
    }

    /// Carries out `invocation` on the source file it names, linking with `toolchain`. Returns the run's result, and
    /// throws when `rayoc` itself can't do the work.
    private static func perform(_ invocation: Invocation, toolchain: Toolchain, programOutput: ProgramOutput,
                                readFile: (String) -> [UInt8]?) throws -> RunResult {
        // Read the source, once a build knows where its executable goes, so a bad path fails before the read.
        let executable = invocation.command == .build ? try executable(building: invocation.path) : nil
        // A file that can't be read stops the run.
        guard let source = readFile(invocation.path) else { throw Failure("can't read '\(invocation.path)'") }

        // Check the program, which is all `check` asks for.
        let (program, diagnostics) = checkAndLower(source)
        // A program with errors fails the run with them.
        guard let program else { return failure(diagnostics, in: invocation.path) }
        // `check` succeeds on a program without errors.
        if invocation.command == .check { return RunResult(exitCode: 0, output: "", errors: "") }

        // Compile the program to object code, with the checks and optimisation of the build's mode.
        let objectCode = try LLVMEmitter.objectCode(for: program, sourcePath: invocation.path,
                                                    checksOverflow: invocation.mode == .debug,
                                                    optimizes: invocation.mode == .release)

        // `build` leaves the executable beside the source.
        if let executable {
            try toolchain.link(objectCode, to: executable)
            return RunResult(exitCode: 0, output: "", errors: "")
        }
        // `run` runs the program from an executable that it removes once the program ends.
        return try toolchain.linkAndRun(objectCode, output: programOutput)
    }

    /// Returns `source` checked and lowered to Rayo IR, or nil with the errors that reject it, which all come from
    /// the first stage of compilation that finds any.
    private static func checkAndLower(_ source: [UInt8]) -> (program: IRProgram?, diagnostics: [Diagnostic]) {
        let (file, diagnostics) = Parser.parse(source)
        guard diagnostics.isEmpty else { return (nil, diagnostics) }

        let checked = Checker.check(file)
        guard let program = checked.program else { return (nil, checked.diagnostics) }

        let lowered = Lowering.lower(program)
        let ownershipErrors = InitializationChecker.check(lowered)
        guard ownershipErrors.isEmpty else { return (nil, ownershipErrors) }

        return (lowered, [])
    }

    /// The executable that `build` writes for the source at `path`: `path` without its `.rayo`. Throws when `path`
    /// doesn't end in `.rayo`, or has no name before it.
    private static func executable(building path: String) throws(Failure) -> URL {
        // A source without the extension would leave the executable on top of it.
        guard path.hasSuffix(".rayo") else { throw Failure("'\(path)' doesn't end in '.rayo'") }

        // An empty name, '.' or '..' would name the source's own directory.
        let name = URL(fileURLWithPath: path).lastPathComponent.dropLast(".rayo".count)
        guard !name.isEmpty && name != "." && name != ".." else {
            throw Failure("'\(path)' has no name before '.rayo'")
        }

        return URL(fileURLWithPath: String(path.dropLast(".rayo".count)))
    }

    /// The result of a run that `error` stopped, which reports it as `rayoc`'s own error.
    private static func failure(reporting error: any Error) -> RunResult {
        switch error {
        case let failure as Failure: return Self.failure(failure.message)
        case let error as LLVMError: return Self.failure("internal error: \(error.message)")
        default: return Self.failure(error.localizedDescription)
        }
    }

    /// The result of a run that stops with `message` as `rayoc`'s own error.
    private static func failure(_ message: String) -> RunResult {
        RunResult(exitCode: 1, output: "", errors: "rayoc: \(message)\n")
    }

    /// The result of a run whose program `diagnostics` reject, each shown after the source's `path`.
    private static func failure(_ diagnostics: [Diagnostic], in path: String) -> RunResult {
        let errors = diagnostics.map { "\(path):\($0)\n" }.joined()
        return RunResult(exitCode: 1, output: "", errors: errors, diagnostics: diagnostics)
    }
}
