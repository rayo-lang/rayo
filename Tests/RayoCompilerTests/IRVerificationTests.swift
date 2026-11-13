@testable import RayoCompiler
import RayoIR
import RayoSema
import Testing

/// A program whose `main`, which returns nothing, ends in `terminator`, and holds one Bool.
private func program(endingIn terminator: Terminator) -> IRProgram {
    var functions = FunctionTable()
    let main = functions.declare(FunctionDeclaration(name: "main()", parameters: [], result: .void, kind: .written))
    let body = IRBody(locals: [.temporary(.bool)], blocks: [BasicBlock(statements: [], terminator: terminator)])
    return IRProgram(types: .empty, functions: functions, bodies: [main: body], main: main)
}

@Suite("Verifying the IR a stage gives")
struct IRVerificationTests {
    @Test func `IR that breaks its types stops the compile with an internal error`() {
        let returnsBool = program(endingIn: .return(.constant(.bool(true))))
        let violation = "the IR returns a value of type Bool from a function that returns Void"
        let message = "internal error: in 'main()': \(violation)"
        #expect(throws: CompilationError.failed(message)) { try VerifyIR().run(returnsBool) }
    }

    @Test func `IR that keeps its types goes on as it is`() throws {
        let returnsNothing = program(endingIn: .return(nil))
        #expect(try VerifyIR().run(returnsNothing) == returnsNothing)
    }
}
