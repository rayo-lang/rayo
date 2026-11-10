internal import CLLVM

/// An LLVM function, with the type that a call to it names.
struct FunctionValue {
    let value: LLVMValueRef
    let type: LLVMTypeRef
}
