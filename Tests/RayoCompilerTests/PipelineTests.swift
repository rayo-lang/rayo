import Testing
import RayoDiagnostics
@testable import RayoCompiler
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

/// An error at `line` of the file.
private func error(on line: Int) -> Diagnostic {
    let start = SourceLocation(line: line, column: 1, offset: line * 10)
    return Diagnostic(.noMain, at: SourceRange(start, start))
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
            StopOnErrors<String>()
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
            StopOnErrors<String>()
            Record(log: log)
        }
        var errors: [Diagnostic] = []
        let gathered = [error(on: 1), error(on: 2), error(on: 3)]
        #expect(throws: CompilationError.rejected(gathered)) { try steps.run(">", errors: &errors) }
        #expect(log.texts.isEmpty)
    }

    @Test func `a step that gives nothing skips the steps up to the next stop, which ends the compile`() {
        let log = Log()
        let steps = pipeline {
            Report(diagnostics: [error(on: 1)])
            GiveUp(diagnostics: [error(on: 2)])
            Record(log: log)
            Report(diagnostics: [error(on: 3)])
            StopOnErrors<String>()
            Record(log: log)
        }
        var errors: [Diagnostic] = []
        let gathered = [error(on: 1), error(on: 2)]
        #expect(throws: CompilationError.rejected(gathered)) { try steps.run(">", errors: &errors) }
        #expect(log.texts.isEmpty)
    }
}
