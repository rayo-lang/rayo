import CLLVM
import LLVM
@testable import RayoLLVM
import Testing

struct ReadinessTests {
    @Test(arguments: Build.allCases)
    func `a module whose context LLVM reported an error in isn't ready, and says the error`(build: Build) throws {
        try withProgramModule(for: build) { programModule in
            // A link of a module that defines a function the module defines too fails, and LLVM reports why.
            let module = programModule.module
            let twice = module.addFunction("twice", taking: [], returning: module.void)
            LLVMPositionBuilderAtEnd(module.builder, module.appendBlock(to: twice.value, named: "entry"))
            LLVMBuildRetVoid(module.builder)
            let other = try module.parse(Array("define void @twice() {\n  ret void\n}\n".utf8), named: "other.ll")
            // The link consumes `other`, which a closure of `#expect(throws:)` can't.
            do { try module.link(other) } catch {}

            var thrown: LLVMError?
            do throws(LLVMError) {
                try module.ready(for: programModule.target, exporting: ["twice"])
            } catch {
                thrown = error
            }
            #expect(thrown == LLVMError(message: """
                LLVM reported errors:
                Linking globals named 'twice': symbol multiply defined!
                """))
        }
    }
}
