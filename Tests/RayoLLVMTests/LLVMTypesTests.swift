import CLLVM
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types of values")
struct LLVMTypesTests {
    @Test(arguments: [(RayoType.int, UInt32(64)), (RayoType.bool, UInt32(1))])
    func `each scalar is held in an integer of its width`(type: RayoType, width: UInt32) throws(LLVMError) {
        let types = LLVMTypes(in: ModuleBuilder(named: "types", for: try TargetMachine(optimizes: false)))
        let llvmType = types.llvmType(type)
        #expect(LLVMGetTypeKind(llvmType) == LLVMIntegerTypeKind)
        #expect(LLVMGetIntTypeWidth(llvmType) == width)
    }

    @Test func `a function that returns nothing returns void`() throws(LLVMError) {
        let types = LLVMTypes(in: ModuleBuilder(named: "types", for: try TargetMachine(optimizes: false)))
        #expect(LLVMGetTypeKind(types.llvmType(.void)) == LLVMVoidTypeKind)
    }
}
