@testable import RayoCompiler
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
        #expect(throws: CompilationError.failed(message)) { try Compiler.verified(returnsBool, from: .ownership) }
    }
    #else
    @Test func `in a release build, IR that breaks its types goes on unchecked`() throws {
        let returnsBool = try program(endingIn: "return true")
        #expect(try Compiler.verified(returnsBool, from: .ownership) == returnsBool)
    }
    #endif

    @Test func `IR that keeps its types goes on as it is`() throws {
        let returnsNothing = try program(endingIn: "return")
        #expect(try Compiler.verified(returnsNothing, from: .ownership) == returnsNothing)
    }
}
