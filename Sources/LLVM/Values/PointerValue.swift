package import CLLVM

/// An LLVM pointer: to a stack slot, or to a global.
public struct PointerValue: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    package init(_ ref: LLVMValueRef) {
        self.ref = ref
    }

    public var anyValue: AnyValue { AnyValue(ref) }
}
