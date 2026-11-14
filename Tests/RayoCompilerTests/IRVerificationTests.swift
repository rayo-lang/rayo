@testable import RayoCompiler
import RayoDiagnostics
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
    #if DEBUG
    @Test func `in a debug build, IR that breaks its types stops the compile with an internal error`() {
        let returnsBool = program(endingIn: .return(.constant(.bool(true))))
        let violation = "the IR returns a value of type Bool from a function that returns Void"
        let message = "internal error: in 'main()': \(violation)"
        var errors: [Diagnostic] = []
        #expect(throws: CompilationError.failed(message)) { try VerifyIR().run(returnsBool, errors: &errors) }
    }
    #else
    @Test func `in a release build, IR that breaks its types goes on unchecked`() throws {
        let returnsBool = program(endingIn: .return(.constant(.bool(true))))
        var errors: [Diagnostic] = []
        #expect(try VerifyIR().run(returnsBool, errors: &errors) == returnsBool)
    }
    #endif

    @Test func `IR that keeps its types goes on as it is`() throws {
        let returnsNothing = program(endingIn: .return(nil))
        var errors: [Diagnostic] = []
        #expect(try VerifyIR().run(returnsNothing, errors: &errors) == returnsNothing)
    }

    @Test func `the front end verifies the IR that lowering gives, before any stage reads it`() {
        // The front end's steps chain in the order it runs them, and its type names each step.
        let frontEnd = Compiler.frontEnd(readFile: { _ in nil })
        let steps = String(describing: type(of: frontEnd))
        #expect(steps.contains("Lower>, VerifyIR>, CheckParameterMoves>"))
    }
}
