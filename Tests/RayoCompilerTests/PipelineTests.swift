import Testing
@testable import RayoDiagnostics
@testable import RayoCompiler
import RayoIR
import RayoSema
import RayoSource

/// Adds its letter to the end of the text it's given.
private struct Append: CompilationStep {
    var letter: Character

    func run(_ text: String, errors: inout [Diagnostic]) -> String? {
        text + String(letter)
    }
}

/// Fails with its message, whatever text it's given.
private struct Fail: CompilationStep {
    var message: String

    func run(_ text: String, errors: inout [Diagnostic]) throws(CompilationError) -> String? {
        throw .failed(message)
    }
}

/// The texts that `Record` steps were given, in the order they were given them.
private final class Log {
    var texts: [String] = []
}

/// Adds the text it's given to its log, and gives the text on.
private struct Record: CompilationStep {
    var log: Log

    func run(_ text: String, errors: inout [Diagnostic]) -> String? {
        log.texts.append(text)
        return text
    }
}

/// Finds `diagnostics` in the text it's given, and gives the text on.
private struct Report: CompilationStep {
    var diagnostics: [Diagnostic]

    func run(_ text: String, errors: inout [Diagnostic]) -> String? {
        errors += diagnostics
        return text
    }
}

/// Finds `diagnostics` in the text it's given, and gives nothing, as a step does that can't make its output.
private struct GiveUp: CompilationStep {
    var diagnostics: [Diagnostic]

    func run(_ text: String, errors: inout [Diagnostic]) -> String? {
        errors += diagnostics
        return nil
    }
}

/// Finds a warning at the start of the program it's given, and gives the program on.
private struct WarnAtStart: CompilationStep {
    func run(_ program: IRProgram, errors: inout [Diagnostic]) -> IRProgram? {
        errors.append(warning(on: 1))
        return program
    }
}

/// What `rayoc` gives when `steps` compile `a.rayo`, printing nothing.
private func rayocResult<Output>(compiling steps: some CompilationStep<String, Output>) -> CompilerResult {
    Compiler.result(compiling: "a.rayo") { errors throws(CompilationError) in
        _ = try steps.run("a.rayo", errors: &errors)
        return ""
    }
}

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

struct PipelineTests {
    @Test func `a pipeline runs its steps in order, each on what the step before it gave`() throws {
        let steps = pipeline {
            Append(letter: "a")
            Append(letter: "b")
            Append(letter: "c")
        }
        var errors: [Diagnostic] = []
        #expect(try steps.run(">", errors: &errors) == ">abc")
    }

    @Test func `a pipeline of one step gives what the step gives`() {
        var errors: [Diagnostic] = []
        #expect(pipeline { Append(letter: "a") }.run(">", errors: &errors) == ">a")
    }

    @Test func `a step that fails stops the pipeline with its error, and no step after it runs`() {
        let log = Log()
        let steps = pipeline {
            Record(log: log)
            Fail(message: "first")
            Record(log: log)
            Fail(message: "second")
        }
        var errors: [Diagnostic] = []
        #expect(throws: CompilationError.failed("first")) { try steps.run(">", errors: &errors) }
        #expect(log.texts == [">"])
    }

    @Test func `a step's errors go on to the steps after it, which still run`() throws {
        let log = Log()
        let steps = pipeline {
            Report(diagnostics: [error(on: 1)])
            Record(log: log)
            Report(diagnostics: [error(on: 2)])
        }
        var errors: [Diagnostic] = []
        #expect(try steps.run(">", errors: &errors) == ">")
        #expect(log.texts == [">"])
        #expect(errors == [error(on: 1), error(on: 2)])
    }

    @Test func `stopping on errors gives its input on when there are none`() throws {
        let steps = pipeline {
            Append(letter: "a")
            StopOnErrors<String>(warningsAreErrors: false)
            Append(letter: "b")
        }
        var errors: [Diagnostic] = []
        #expect(try steps.run(">", errors: &errors) == ">ab")
    }

    @Test func `stopping on errors ends the compile with every error gathered, in source order`() {
        let log = Log()
        let steps = pipeline {
            Report(diagnostics: [error(on: 3), error(on: 1)])
            Report(diagnostics: [error(on: 2)])
            StopOnErrors<String>(warningsAreErrors: false)
            Record(log: log)
        }
        var errors: [Diagnostic] = []
        let gathered = [error(on: 1), error(on: 2), error(on: 3)]
        #expect(throws: CompilationError.rejected(gathered)) { try steps.run(">", errors: &errors) }
        #expect(log.texts.isEmpty)
    }

    @Test func `stopping on errors gives its input on past warnings, which stay among those gathered`() throws {
        let steps = pipeline {
            Report(diagnostics: [warning(on: 1)])
            StopOnErrors<String>(warningsAreErrors: false)
            Append(letter: "a")
        }
        var errors: [Diagnostic] = []
        #expect(try steps.run(">", errors: &errors) == ">a")
        #expect(errors == [warning(on: 1)])
    }

    @Test func `when warnings are errors, stopping on errors ends the compile on a warning, with every one gathered`() {
        let log = Log()
        let steps = pipeline {
            Report(diagnostics: [warning(on: 3), warning(on: 1)])
            StopOnErrors<String>(warningsAreErrors: true)
            Record(log: log)
        }
        var errors: [Diagnostic] = []
        let gathered = [warning(on: 1), warning(on: 3)]
        #expect(throws: CompilationError.rejected(gathered)) { try steps.run(">", errors: &errors) }
        #expect(log.texts.isEmpty)
    }

    @Test(arguments: [(false, 0), (true, 1)])
    func `a warning is shown as one, and fails the compile only when warnings are errors`(
        warningsAreErrors: Bool, exitCode: Int32,
    ) {
        let steps = pipeline {
            Compiler.frontEnd(readFile: { _ in Array("func main() {}".utf8) })
            WarnAtStart()
            StopOnErrors<IRProgram>(warningsAreErrors: warningsAreErrors)
        }
        let result = rayocResult(compiling: steps)
        #expect(result.exitCode == exitCode)
        #expect(result.diagnostics == [warning(on: 1)])
        #expect(result.errors == """
            a.rayo:1:1: warning[E0201]: a file without a 'main' function is a library, which can't be built into an \
            executable or run

            """)
    }

    @Test func `the warnings found before rayoc can't go on are shown before why`() {
        let steps = pipeline {
            Report(diagnostics: [warning(on: 2)])
            Fail(message: "can't write 'a.o'")
        }
        let result = rayocResult(compiling: steps)
        #expect(result.exitCode == 1)
        #expect(result.errors.hasPrefix("a.rayo:2:1: warning[E0201]: "))
        #expect(result.errors.hasSuffix("\nrayoc: can't write 'a.o'\n"))
    }

    @Test func `a step that gives nothing skips the steps up to the next stop, which ends the compile`() {
        let log = Log()
        let steps = pipeline {
            Report(diagnostics: [error(on: 1)])
            GiveUp(diagnostics: [error(on: 2)])
            Record(log: log)
            Report(diagnostics: [error(on: 3)])
            StopOnErrors<String>(warningsAreErrors: false)
            Record(log: log)
        }
        var errors: [Diagnostic] = []
        let gathered = [error(on: 1), error(on: 2)]
        #expect(throws: CompilationError.rejected(gathered)) { try steps.run(">", errors: &errors) }
        #expect(log.texts.isEmpty)
    }

    @Test(arguments: [(false, false), (true, true)])
    func `a check's error drops the body of the function it is in, so later checks skip it, and a warning drops none`(
        isWarning: Bool, keepsBody: Bool,
    ) throws {
        var errors: [Diagnostic] = []
        let program = try #require(try Compiler.frontEnd(readFile: { _ in Array("func main() {}".utf8) })
            .run("a.rayo", errors: &errors))
        let main = try #require(program.main)
        let found = isWarning ? warning(on: 1) : error(on: 1)
        #expect((program.withoutBodies(failing: [main: [found]]).bodies[main] != nil) == keepsBody)
    }
}
