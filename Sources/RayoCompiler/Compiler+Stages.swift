import RayoDiagnostics
import RayoIR
import RayoLLVM
import RayoOwnership
import RayoSema
import RayoSource
import RayoSyntax

/// The stages a compile runs, and the checks between them, each a function that takes what the stage before it
/// gives. A stage adds the errors and warnings it finds in the program to the compile's list, and throws only when
/// `rayoc` itself can't go on. `accepted(_:errors:)` alone ends a compile for the program's errors.
extension Compiler {
    /// Reads the source file at `path` through `readFile`, checks it, lowers it to Rayo IR, and runs the ownership
    /// checks on the IR, adding the program's errors and warnings to `errors`. It gives the IR the emitter receives,
    /// without the bodies of the functions a stage found failed, or nil when the file isn't UTF-8 text.
    static func frontEnd(
        _ path: String, readFile: (String) -> [UInt8]?, errors: inout [Diagnostic],
    ) throws(CompilationError) -> IRProgram? {
        guard let checked = try checkedProgram(path, readFile: readFile, errors: &errors) else { return nil }
        return try ir(of: checked, errors: &errors)
    }

    /// Reads the source file at `path` through `readFile`, parses it and checks it, adding its errors and warnings to
    /// `errors`. It gives the checked program, without the bodies of the functions that are tainted, or nil when the
    /// file isn't UTF-8 text.
    static func checkedProgram(
        _ path: String, readFile: (String) -> [UInt8]?, errors: inout [Diagnostic],
    ) throws(CompilationError) -> CheckedProgram? {
        let source = try source(at: path, readFile: readFile)
        guard let file = syntaxTree(of: source, errors: &errors) else { return nil }
        return checked(file, errors: &errors)
    }

    /// Lowers `checked` to Rayo IR, and runs the ownership checks on it, adding their errors to `errors`. It gives the
    /// IR the emitter receives, without the bodies of the functions a check found failed.
    static func ir(of checked: CheckedProgram, errors: inout [Diagnostic]) throws(CompilationError) -> IRProgram {
        let lowered = try verified(Lowering.lower(checked), from: .lowering)
        // The ownership stage writes the end of each access and the retirement of each local into the IR, which is
        // verified again, since it is no longer lowering's.
        return try verified(owned(lowered, errors: &errors), from: .ownership)
    }

    /// The bytes of the source file at `path`, which `readFile` reads. A file it can't read stops the compile.
    private static func source(
        at path: String, readFile: (String) -> [UInt8]?,
    ) throws(CompilationError) -> [UInt8] {
        // A file that can't be read leaves nothing to compile.
        guard let source = readFile(path) else { throw .failed("can't read '\(path)'") }
        return source
    }

    /// Parses `source` into its syntax tree, and adds its syntax errors to `errors`. The tree keeps what failed to
    /// parse, so the stages after this one check the rest; a source that isn't UTF-8 makes no tree.
    private static func syntaxTree(of source: [UInt8], errors: inout [Diagnostic]) -> SourceFile? {
        let (file, diagnostics) = Parser.parse(source)
        errors += diagnostics
        return file
    }

    /// Checks `file`, and gives the program it makes, adding its errors and warnings to `errors`. The program holds no
    /// body for a function whose body is tainted, so the stages after this one skip it.
    private static func checked(_ file: SourceFile, errors: inout [Diagnostic]) -> CheckedProgram {
        let checked = Checker.check(file)
        errors += checked.diagnostics
        return checked.program
    }

    /// Runs the ownership checks on `program`, adding their errors to `errors`, and gives the program with the end of
    /// each access and the retirement of each local written in, without the bodies of the functions a check found
    /// failed.
    private static func owned(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram {
        let (owned, found) = OwnershipChecker.check(program)
        errors += found.values.joined()
        return owned
    }

    /// `program`, which `stage` gave, once a debug build of `rayoc` has checked it keeps the IR's rules: its types, the
    /// checks of the indices it finds elements by, and, for the ownership stage's IR, where its accesses end and its
    /// locals retire.
    static func verified(_ program: IRProgram, from stage: IRStage) throws(CompilationError) -> IRProgram {
        // A release build of `rayoc` takes its stages' IR on trust, and spends no time checking it.
        #if DEBUG
        // IR that breaks its rules is a fault in `rayoc`, never in the program.
        if let violation = IRVerifier.verify(program, from: stage) { throw .failed("internal error: \(violation)") }
        #endif
        return program
    }

    /// The executable that `program` makes, when it has a `main`, which an executable starts at. A library, which has
    /// none, is reported in `errors`, and makes none.
    static func executable(of program: IRProgram, errors: inout [Diagnostic]) -> IRExecutable? {
        guard let executable = IRExecutable(program) else {
            // A function that failed to parse may have been the `main`, so its absence isn't reported. A library is
            // reported at the start of its file, since no line of it is wrong.
            if !program.mainMayHaveFailed {
                let start = SourceLocation(line: 1, column: 1, offset: 0)
                errors.append(Diagnostic(.noMain, at: SourceRange(start, start)))
            }
            return nil
        }
        return executable
    }

    /// `value`, unless `errors` hold an error, which ends the compile with every error and warning in `errors`, in
    /// source order. A stage gives nil only when the program has errors, so a nil `value` ends the compile too.
    static func accepted<Value>(_ value: Value?, errors: [Diagnostic]) throws(CompilationError) -> Value {
        let endsCompile = errors.contains { $0.severity == .error }
        guard !endsCompile, let value else { throw .rejected(errors.inSourceOrder) }
        return value
    }

    /// The object code for the host that `executable` compiles to, as a build of the source at `sourcePath`.
    static func objectCode(
        of executable: IRExecutable, build: Build, sourcePath: String,
    ) throws(CompilationError) -> [UInt8] {
        do {
            return try LLVMEmitter.objectCode(for: executable, sourcePath: sourcePath, build: build)
        } catch {
            // LLVM fails only through a fault in rayoc or in LLVM, never one in the program.
            throw .failed("internal error: \(error.message)")
        }
    }

    /// Writes `objectCode` to the file at `path` through `writeFile`, which returns whether it could.
    static func write(
        _ objectCode: [UInt8], to path: String, writeFile: (String, [UInt8]) -> Bool,
    ) throws(CompilationError) {
        // A file that can't be written leaves the compile without its result.
        guard writeFile(path, objectCode) else { throw .failed("can't write '\(path)'") }
    }
}
