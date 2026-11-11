import CLLVM
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types of values")
struct ValueTypeTests {
    @Test(arguments: [(RayoType.int, UInt32(64)), (RayoType.bool, UInt32(1))])
    func `an Int is held in a 64-bit integer, and a Bool in a 1-bit one`(
        type: RayoType, width: UInt32,
    ) throws(LLVMError) {
        let emitting = try ProgramModule(for: .debug)
        // The module owns its LLVM types, so it lives until the checks have read them.
        withExtendedLifetime(emitting) {
            let llvmType = emitting.emitter.types.llvmType(type)
            #expect(LLVMGetTypeKind(llvmType) == LLVMIntegerTypeKind)
            #expect(LLVMGetIntTypeWidth(llvmType) == width)
        }
    }

    @Test func `a function that returns nothing returns LLVM's void`() throws(LLVMError) {
        let emitting = try ProgramModule(for: .debug)
        // The module owns its LLVM types, so it lives until the check has read them.
        withExtendedLifetime(emitting) {
            #expect(LLVMGetTypeKind(emitting.emitter.types.llvmType(.void)) == LLVMVoidTypeKind)
        }
    }
}
