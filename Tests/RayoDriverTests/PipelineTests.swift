import Testing
import RayoDiagnostics
@testable import RayoDriver
import RayoSource

/// Adds its letter to the end of the text it's given.
private struct Append: CompilationStep {
    var letter: Character

    func run(_ text: String) -> String {
        text + String(letter)
    }
}

/// Fails with its message, whatever text it's given.
private struct Fail: CompilationStep {
    var message: String

    func run(_ text: String) throws(CompilationError) -> String {
        throw .failed(message)
    }
}

/// Rejects the text it's given with `diagnostics`.
private struct Reject: CompilationStep {
    var diagnostics: [Diagnostic]

    func run(_ text: String) throws(CompilationError) -> String {
        throw .rejected(diagnostics)
    }
}

struct PipelineTests {
    @Test func `a pipeline runs its steps in order, each on what the step before it gave`() throws {
        let steps = pipeline {
            Append(letter: "a")
            Append(letter: "b")
            Append(letter: "c")
        }
        #expect(try steps.run(">") == ">abc")
    }

    @Test func `a pipeline of one step gives what the step gives`() {
        #expect(pipeline { Append(letter: "a") }.run(">") == ">a")
    }

    @Test func `a step that fails stops the pipeline, and no step after it runs`() {
        let steps = pipeline {
            Append(letter: "a")
            Fail(message: "first")
            Fail(message: "second")
        }
        #expect(throws: CompilationError.failed("first")) { try steps.run(">") }
    }

    @Test func `a rejection gives every diagnostic of the step that rejects, as the step gave them`() {
        let start = SourceLocation(line: 2, column: 5, offset: 20)
        let diagnostics = [
            Diagnostic(.notDeclared(name: "x"), at: SourceRange(start, start)),
            Diagnostic(.noMain, at: SourceRange(start, start)),
        ]
        let steps = pipeline {
            Append(letter: "a")
            Reject(diagnostics: diagnostics)
            Append(letter: "b")
        }
        #expect(throws: CompilationError.rejected(diagnostics)) { try steps.run(">") }
    }
}
