import Testing
@testable import RayoDiagnostics
@testable import RayoCompiler
import RayoIR
import RayoSema
import RayoSource

/// An error at `line` of the file.
private func error(on line: Int) -> Diagnostic {
    let start = SourceLocation(line: line, column: 1, offset: line * 10)
    return Diagnostic(.noMain, at: SourceRange(start, start))
}

/// A warning at `line` of the file. No code is a warning, so it takes an error's code.
private func warning(on line: Int) -> Diagnostic {
    let start = SourceLocation(line: line, column: 1, offset: line * 10)
    return Diagnostic(.noMain, severity: .warning, at: SourceRange(start, start))
}

/// Reads every path as a file that holds an empty `main`.
private func emptyMain(_ path: String) -> [UInt8]? {
    Array("func main() {}".utf8)
}

struct PipelineTests {
    @Test func `accepting a stage's result gives it on when the program has no errors`() throws {
        #expect(try Compiler.accepted(">", errors: []) == ">")
    }

    @Test func `accepting a stage's result ends the compile with every error gathered, in source order`() {
        let errors = [error(on: 3), error(on: 1), error(on: 2)]
        let gathered = [error(on: 1), error(on: 2), error(on: 3)]
        #expect(throws: CompilationError.rejected(gathered)) {
            try Compiler.accepted(">", errors: errors)
        }
    }

    @Test func `accepting a stage's result gives it on past warnings`() throws {
        #expect(try Compiler.accepted(">", errors: [warning(on: 1)]) == ">")
    }

    @Test func `a stage that gives nothing ends the compile with the errors gathered`() {
        let nothing: String? = nil
        #expect(throws: CompilationError.rejected([error(on: 1)])) {
            try Compiler.accepted(nothing, errors: [error(on: 1)])
        }
    }

    @Test func `a warning is shown as one, and doesn't fail the compile`() {
        let result = Compiler.result(compiling: "a.rayo") { errors throws(CompilationError) in
            let program = try Compiler.frontEnd("a.rayo", readFile: emptyMain, errors: &errors)
            errors.append(warning(on: 1))
            _ = try Compiler.accepted(program, errors: errors)
            return ""
        }
        #expect(result.exitCode == 0)
        #expect(result.diagnostics == [warning(on: 1)])
        #expect(result.errors == """
            a.rayo:1:1: warning[E0201]: the file has no 'main' function, so it can't be built into an \
            executable or run

            """)
    }

    @Test func `the warnings found before rayoc can't go on are shown before why`() {
        let result = Compiler.result(compiling: "a.rayo") { errors throws(CompilationError) in
            errors.append(warning(on: 2))
            try Compiler.write([], to: "a.o") { _, _ in false }
            return ""
        }
        #expect(result.exitCode == 1)
        #expect(result.errors.hasPrefix("a.rayo:2:1: warning[E0201]: "))
        #expect(result.errors.hasSuffix("\nrayoc: can't write 'a.o'\n"))
    }

    @Test func `a file that can't be read stops the compile with why`() {
        var errors: [Diagnostic] = []
        #expect(throws: CompilationError.failed("can't read 'a.rayo'")) {
            try Compiler.frontEnd("a.rayo", readFile: { _ in nil }, errors: &errors)
        }
    }
}
