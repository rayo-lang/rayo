@testable import RayoCompiler
import RayoDiagnostics
import RayoIR
import Testing

/// A program whose `main`, which returns nothing, ends in `terminator`, written as IR text.
private func program(endingIn terminator: String) throws -> IRProgram {
    try IRParser.program(from: """
        main "main()"
        func "main()"() -> Void {
        bb0:
          \(terminator)
        }
        """)
}

@Suite("Verifying the IR a stage gives")
struct IRVerificationTests {
    #if DEBUG
    @Test func `in a debug build, IR that breaks its types stops the compile with an internal error`() throws {
        let returnsBool = try program(endingIn: "return true")
        let violation = "the IR returns a value of type Bool from a function that returns Void"
        let message = "internal error: in 'main()': \(violation)"
        var errors: [Diagnostic] = []
        #expect(throws: CompilationError.failed(message)) { try VerifyIR().run(returnsBool, errors: &errors) }
    }
    #else
    @Test func `in a release build, IR that breaks its types goes on unchecked`() throws {
        let returnsBool = try program(endingIn: "return true")
        var errors: [Diagnostic] = []
        #expect(try VerifyIR().run(returnsBool, errors: &errors) == returnsBool)
    }
    #endif

    @Test func `IR that keeps its types goes on as it is`() throws {
        let returnsNothing = try program(endingIn: "return")
        var errors: [Diagnostic] = []
        #expect(try VerifyIR().run(returnsNothing, errors: &errors) == returnsNothing)
    }

    @Test func `the front end verifies the IR that lowering gives, before any stage reads it`() {
        // The front end's steps chain in the order it runs them, and its type names each step.
        let frontEnd = Compiler.frontEnd(readFile: { _ in nil })
        let steps = String(describing: type(of: frontEnd))
        #expect(steps.contains("Lower, VerifyIR>, CheckMoves>"))
    }
}
