import LLVM
@testable import RayoLLVM
import Testing

struct ReadinessTests {
    @Test(arguments: Build.allCases)
    func `a module whose context LLVM reported an error in isn't ready, and says the error`(build: Build) throws {
        try withProgramModule(for: build) { programModule in
            // A link of a module that defines a function the module defines too fails, and LLVM reports why.
            defineTwice(in: programModule.emitter)
            let ir = Array("define void @twice() {\n  ret void\n}\n".utf8)
            let other = try programModule.emitter.context.parseModule(ir, named: "other.ll")
            other.target = programModule.emitter.module.target
            other.dataLayout = programModule.emitter.module.dataLayout
            // The link consumes `other`, which a closure of `#expect(throws:)` can't.
            var linkFailed = false
            do { try programModule.emitter.module.link(other) } catch { linkFailed = true }
            #expect(linkFailed)

            var thrown: LLVMError?
            do throws(LLVMError) {
                try LLVMEmitter.ready(programModule.emitter.module, for: programModule.target, exporting: ["twice"])
            } catch {
                thrown = error
            }
            #expect(thrown == LLVMError(message: """
                LLVM reported errors:
                Linking globals named 'twice': symbol multiply defined!
                """))
        }
    }

    /// Defines `twice() -> void` in `program`'s module.
    private func defineTwice(in program: borrowing ProgramEmitter) {
        let type = program.context.functionType(returning: program.context.voidType, taking: [])
        let twice = program.module.addFunction(named: "twice", type: type)
        program.builder.position(atEndOf: program.context.appendBlock(named: "entry", to: twice))
        program.builder.returnVoid()
    }
}
