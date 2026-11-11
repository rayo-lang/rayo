import RayoIR

/// The compiler, `rayoc`, which checks a source file or compiles it to object code for the host.
public enum Compiler {
    static let usage = """
        usage: rayoc --check [--] <file>
               rayoc [--debug | --release] -o <object file> [--] <file>

        options:
          --check    check the file and report its errors, writing nothing
          -o         compile the file to object code for the host, and write it to the object file
          --         end the options, so that the file may be named like one

        build modes, with -o:
          --debug    integer overflow panics, and the object code isn't optimised
          --release  integer overflow wraps, and the object code is optimised; a compile that names no mode is a
                     release compile

        """

    /// What the arguments ask `rayoc` to do.
    private struct Invocation {
        /// What a run of `rayoc` makes of the source file.
        enum Output {
            /// Nothing: the file is only checked.
            case check
            /// Object code, written to the file at `path`, in `mode`.
            case objectFile(path: String, mode: BuildMode)
        }

        /// Why the arguments don't make a compile `rayoc` can run.
        struct UsageError: Error {}

        var output: Output
        var path: String

        init(_ arguments: [String]) throws(UsageError) {
            // Read each option before the file, each at most once.
            var checks = false
            var objectFile: String?
            var mode: BuildMode?
            var optionsEnded = false
            var operands = arguments[...]
            while !optionsEnded, operands.count > 1, let option = operands.popFirst() {
                if option == "--" {
                    // `--` ends the options, so the operand after it is the file, whatever it is named.
                    optionsEnded = true
                } else if option == "--check", !checks {
                    // `--check` asks for the file to be checked only.
                    checks = true
                } else if let newMode = BuildMode(rawValue: option), mode == nil {
                    // A build mode says how the object code is built.
                    mode = newMode
                } else if option == "-o", objectFile == nil, operands.count > 1, let path = operands.first,
                          !Self.isOption(path) {
                    // `-o` takes the operand after it as the object file's path.
                    objectFile = path
                    operands = operands.dropFirst()
                } else {
                    // An option rayoc doesn't take, or one given twice, asks for no compile.
                    throw UsageError()
                }
            }

            // The one operand left is the source file; before a `--`, an option there leaves the arguments
            // without one.
            guard operands.count == 1, let path = operands.first, optionsEnded || !Self.isOption(path) else {
                throw UsageError()
            }
            self.path = path

            // Decide what the run makes of the file.
            switch (checks, objectFile) {
            // `--check` alone checks the file; a build mode would change no check.
            case (true, nil) where mode == nil:
                output = .check
            // `-o` alone writes the file's object code, in release mode unless a mode is named.
            case (false, let objectFile?):
                output = .objectFile(path: objectFile, mode: mode ?? .release)
            // Both, or neither, or a mode with `--check`, ask for no one compile.
            default:
                throw UsageError()
            }
        }

        /// Whether `operand` is one of `rayoc`'s options, which leaves the arguments without a file.
        private static func isOption(_ operand: String) -> Bool {
            operand == "--check" || operand == "-o" || operand == "--" || BuildMode(rawValue: operand) != nil
        }
    }

    /// Runs `rayoc` with `arguments`, which exclude the program's name. It reads the source file through
    /// `readFile`, which returns nil for a file it can't read, and writes the object file through `writeFile`,
    /// which returns whether it wrote it.
    public static func run(
        _ arguments: [String], readFile: @escaping (String) -> [UInt8]?,
        writeFile: @escaping (String, [UInt8]) -> Bool,
    ) -> CompilerResult {
        // Read what the arguments ask for.
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            // Arguments that ask for no compile are reported with how to use rayoc.
            return CompilerResult(exitCode: 2, errors: usage)
        }

        // Compile the file as the arguments ask.
        do {
            try compile(invocation, readFile: readFile, writeFile: writeFile)
            return CompilerResult(exitCode: 0, errors: "")
        } catch {
            // A compile that stops is reported with why.
            return result(of: error, in: invocation.path)
        }
    }

    /// Checks the source file `invocation` names, and writes its object code when it asks for that.
    private static func compile(
        _ invocation: Invocation, readFile: @escaping (String) -> [UInt8]?,
        writeFile: @escaping (String, [UInt8]) -> Bool,
    ) throws(CompilationError) {
        switch invocation.output {
        case .check:
            _ = try frontEnd(readFile: readFile).run(invocation.path)
        case .objectFile(let path, let mode):
            try pipeline {
                frontEnd(readFile: readFile)
                Emit(mode: mode, sourcePath: invocation.path)
                WriteObject(path: path, writeFile: writeFile)
            }.run(invocation.path)
        }
    }

    /// The step that reads the source file at a path through `readFile`, checks it, and lowers it to Rayo IR.
    private static func frontEnd(readFile: @escaping (String) -> [UInt8]?) -> some CompilationStep<String, IRProgram> {
        pipeline {
            ReadSource(readFile: readFile)
            Parse()
            Check()
            Lower()
            CheckOwnership()
        }
    }

    /// Returns what `rayoc` gives when a compile of the file at `path` stops with `error`.
    private static func result(of error: CompilationError, in path: String) -> CompilerResult {
        switch error {
        // Each of the program's errors is shown at its place in the file.
        case .rejected(let diagnostics):
            CompilerResult(exitCode: 1, errors: diagnostics.map { "\(path):\($0)\n" }.joined(),
                           diagnostics: diagnostics)
        // A reason of rayoc's own is shown as its message.
        case .failed(let message):
            CompilerResult(exitCode: 1, errors: "rayoc: \(message)\n")
        }
    }
}
