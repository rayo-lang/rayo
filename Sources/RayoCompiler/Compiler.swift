import RayoDiagnostics
import RayoIR
import RayoLLVM
import RayoSema
import RayoSyntax

/// The compiler, `rayoc`, which checks a source file, prints what a stage makes of it, or compiles it to object code
/// for the host.
public enum Compiler {
    static let usage = """
        usage: rayoc --check [--] <file>
               rayoc --emit=checked|ir [--] <file>
               rayoc [--debug | --release] -o <object file> [--] <file>

        options:
          --check         check the file and report its errors and warnings, writing nothing
          --emit=checked  check the file, and print its checked program
          --emit=ir       check the file, and print its Rayo IR
          -o              compile the file to object code for the host, and write it to the object file
          --              end the options, so that the file may be named like one

        build modes, with -o:
          --debug         integer overflow panics, and the object code isn't optimised
          --release       integer overflow wraps, and the object code is optimised; a compile that names no mode
                          is a release compile

        """

    /// What the arguments ask `rayoc` to do.
    private struct Invocation {
        /// What a run of `rayoc` makes of the source file.
        enum Output {
            /// Nothing: the file is only checked.
            case check
            /// What a stage makes of the file, printed once the file checks.
            case dump(Dump)
            /// Object code, written to the file at `path`, as `build` makes it.
            case objectFile(path: String, build: Build)
        }

        /// What a stage makes of a file, as `rayoc` prints it.
        enum Dump {
            /// The checked program, which checking makes.
            case checked
            /// The Rayo IR, as lowering makes it and the ownership stage ends its accesses.
            case ir

            /// The dump `option` asks for, as `rayoc`'s command line spells it, or nil where it asks for none.
            init?(option: String) {
                switch option {
                case "--emit=checked": self = .checked
                case "--emit=ir": self = .ir
                default: return nil
                }
            }
        }

        /// Why the arguments don't make a compile `rayoc` can run.
        struct UsageError: Error {}

        var output: Output
        var path: String

        init(_ arguments: [String]) throws(UsageError) {
            // Read each option before the file, each at most once.
            var checks = false
            var dump: Dump?
            var objectFile: String?
            var build: Build?
            var optionsEnded = false
            var operands = arguments[...]
            while !optionsEnded, operands.count > 1, let option = operands.popFirst() {
                if option == "--" {
                    // `--` ends the options, so the operand after it is the file, whatever it is named.
                    optionsEnded = true
                } else if option == "--check", !checks {
                    // `--check` asks for the file to be checked only.
                    checks = true
                } else if let newDump = Dump(option: option), dump == nil {
                    // `--emit` asks for what a stage makes of the file to be printed.
                    dump = newDump
                } else if let newBuild = Build(option: option), build == nil {
                    // A build mode says how the object code is built.
                    build = newBuild
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
            switch (checks, dump, objectFile) {
            // `--check` alone checks the file; a build mode would change no check.
            case (true, nil, nil) where build == nil:
                output = .check
            // `--emit` alone prints a dump; a build mode would change no dump.
            case (false, let dump?, nil) where build == nil:
                output = .dump(dump)
            // `-o` alone writes the file's object code, in release mode unless a mode is named.
            case (false, nil, let objectFile?):
                output = .objectFile(path: objectFile, build: build ?? .release)
            // More than one of them, or none, or a mode without `-o`, ask for no one compile.
            default:
                throw UsageError()
            }
        }

        /// Whether `operand` is one of `rayoc`'s options, which leaves the arguments without a file.
        private static func isOption(_ operand: String) -> Bool {
            ["--check", "-o", "--"].contains(operand) || Dump(option: operand) != nil
                || Build(option: operand) != nil
        }
    }

    /// Runs `rayoc` with `arguments`, which exclude the program's name. It reads the source file through
    /// `readFile`, which returns nil for a file it can't read, and writes the object file through `writeFile`,
    /// which returns whether it wrote it.
    public static func run(
        _ arguments: [String], readFile: (String) -> [UInt8]?, writeFile: (String, [UInt8]) -> Bool,
    ) -> CompilerResult {
        // Read what the arguments ask for.
        let invocation: Invocation
        do {
            invocation = try Invocation(arguments)
        } catch {
            // Arguments that ask for no compile are reported with how to use rayoc.
            return CompilerResult(exitCode: 2, errors: usage)
        }

        // Compile the file as the arguments ask, on a thread whose stack lets every stage recurse through the deepest
        // expression the parser accepts.
        let compiled = StageThread.run {
            result(compiling: invocation.path) { errors throws(CompilationError) in
                try compile(invocation, readFile: readFile, writeFile: writeFile, errors: &errors)
            }
        }
        return compiled ?? CompilerResult(exitCode: 1, errors: "rayoc: can't start a thread to compile on\n")
    }

    /// Returns what `rayoc` gives when `compile` compiles the source file at `path`, adding the program's errors and
    /// warnings to the list it's given, and returns what `rayoc` prints to its standard output.
    static func result(
        compiling path: String, _ compile: (inout [Diagnostic]) throws(CompilationError) -> String,
    ) -> CompilerResult {
        var diagnostics: [Diagnostic] = []
        let output: String
        do {
            output = try compile(&diagnostics)
        } catch {
            // A compile that stops is reported with why.
            return result(of: error, in: path, warnings: diagnostics.inSourceOrder)
        }

        // A compile that runs to its end found no error, since a stop would have ended it, so it succeeds, and shows
        // the warnings it found.
        let warnings = diagnostics.inSourceOrder
        return CompilerResult(exitCode: 0, errors: shown(warnings, in: path), diagnostics: warnings,
                              standardOutput: output)
    }

    /// Checks the source file `invocation` names, and writes its object code when it asks for that, adding the
    /// program's errors and warnings to `errors`. Returns what `rayoc` prints to its standard output: the dump
    /// `invocation` asks for, or nothing.
    ///
    /// Each stage skips only what an earlier stage found failed, and the compile ends on the program's errors only
    /// before it prints or writes anything. So every error that every stage finds is reported together.
    private static func compile(
        _ invocation: Invocation, readFile: (String) -> [UInt8]?, writeFile: (String, [UInt8]) -> Bool,
        errors: inout [Diagnostic],
    ) throws(CompilationError) -> String {
        let path = invocation.path
        return switch invocation.output {
        case .check:
            try check(path, readFile: readFile, errors: &errors)
        case .dump(.checked):
            try checkedProgramText(of: path, readFile: readFile, errors: &errors)
        case .dump(.ir):
            try irText(of: path, readFile: readFile, errors: &errors)
        case .objectFile(let objectPath, let build):
            try writeObjectCode(of: path, to: objectPath, build: build, readFile: readFile, writeFile: writeFile,
                                errors: &errors)
        }
    }

    /// Checks the source file at `path`, and prints nothing.
    private static func check(
        _ path: String, readFile: (String) -> [UInt8]?, errors: inout [Diagnostic],
    ) throws(CompilationError) -> String {
        let program = try frontEnd(path, readFile: readFile, errors: &errors)
        _ = try accepted(program, errors: errors)
        return ""
    }

    /// The checked program of the source file at `path`, as text, once the stages after checking accept it too.
    private static func checkedProgramText(
        of path: String, readFile: (String) -> [UInt8]?, errors: inout [Diagnostic],
    ) throws(CompilationError) -> String {
        let checked = try checkedProgram(path, readFile: readFile, errors: &errors)
        // The stages after checking run only for the errors they find, which keep the program from being printed.
        if let checked { _ = try ir(of: checked.program, errors: &errors) }
        return CheckedPrinter.text(of: try accepted(checked, errors: errors).program)
    }

    /// The Rayo IR of the source file at `path`, as text, once it checks.
    private static func irText(
        of path: String, readFile: (String) -> [UInt8]?, errors: inout [Diagnostic],
    ) throws(CompilationError) -> String {
        let program = try frontEnd(path, readFile: readFile, errors: &errors)
        return IRPrinter.text(of: try accepted(program, errors: errors).program)
    }

    /// Compiles the source file at `path` as `build` asks, writes its object code to the file at `objectPath`, and
    /// prints nothing.
    private static func writeObjectCode(
        of path: String, to objectPath: String, build: Build, readFile: (String) -> [UInt8]?,
        writeFile: (String, [UInt8]) -> Bool, errors: inout [Diagnostic],
    ) throws(CompilationError) -> String {
        let program = try frontEnd(path, readFile: readFile, errors: &errors)
        let executable = program.flatMap {
            Self.executable(of: $0.program, mainMayHaveFailed: $0.mainMayHaveFailed, errors: &errors)
        }
        let accepted = try accepted(executable, errors: errors)
        try write(objectCode(of: accepted, build: build, sourcePath: path), to: objectPath, writeFile: writeFile)
        return ""
    }

    /// Returns what `rayoc` gives when a compile of the file at `path` stops with `error`, after finding `warnings`.
    private static func result(
        of error: CompilationError, in path: String, warnings: [Diagnostic],
    ) -> CompilerResult {
        switch error {
        // Each of the program's errors and warnings is shown at its place in the file.
        case .rejected(let diagnostics):
            CompilerResult(exitCode: 1, errors: shown(diagnostics, in: path), diagnostics: diagnostics)
        // A reason of rayoc's own is shown as its message, after the warnings found before it.
        case .failed(let message):
            CompilerResult(exitCode: 1, errors: shown(warnings, in: path) + "rayoc: \(message)\n",
                           diagnostics: warnings)
        }
    }

    /// `diagnostics` as `rayoc` shows them: a line for each, at its place in the file at `path`, and after it a line
    /// for each place it labels.
    private static func shown(_ diagnostics: [Diagnostic], in path: String) -> String {
        let lines = diagnostics.flatMap { [$0.description] + $0.notes }
        return lines.map { "\(path):\($0)\n" }.joined()
    }
}

private extension Build {
    /// The build `option` names, as `rayoc`'s command line spells a build mode.
    init?(option: String) {
        switch option {
        case "--debug": self = .debug
        case "--release": self = .release
        default: return nil
        }
    }
}
