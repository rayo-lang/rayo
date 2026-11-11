import CLLVM
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types of values")
struct ValueTypeTests {
    @Test(arguments: [(RayoType.int, UInt32(64)), (RayoType.bool, UInt32(1))])
    func `an Int is held in a 64-bit integer, and a Bool in a 1-bit one`(type: RayoType, width: UInt32) throws {
        try withProgramModule(for: .debug) { programModule in
            let llvmType = LLVMTypes(in: programModule.module).llvmType(type)
            #expect(LLVMGetTypeKind(llvmType) == LLVMIntegerTypeKind)
            #expect(LLVMGetIntTypeWidth(llvmType) == width)
        }
    }

    @Test func `a function that returns nothing returns LLVM's void`() throws {
        try withProgramModule(for: .debug) { programModule in
            #expect(LLVMGetTypeKind(LLVMTypes(in: programModule.module).llvmType(.void)) == LLVMVoidTypeKind)
        }
    }
}
