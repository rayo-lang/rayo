import CLLVM
@testable import RayoLLVM

/// `type` as LLVM writes it, such as `i64`.
func text(of type: LLVMTypeRef) -> String {
    takeMessage(LLVMPrintTypeToString(type))
}
