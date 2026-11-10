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
        let llvmType = try types().llvmType(type)
        #expect(LLVMGetTypeKind(llvmType) == LLVMIntegerTypeKind)
        #expect(LLVMGetIntTypeWidth(llvmType) == width)
    }

    @Test func `Void is LLVM's void type`() throws(LLVMError) {
        #expect(LLVMGetTypeKind(try types().llvmType(.void)) == LLVMVoidTypeKind)
    }

    /// The LLVM types of the values of a program emitted into a new module.
    private func types() throws(LLVMError) -> LLVMTypes {
        try ProgramModule(optimizes: false).emitter.types
    }
}
