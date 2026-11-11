package import CLLVM

/// A global variable of a module, which holds a value for the whole of a run.
public struct GlobalVariable: GlobalValue, Equatable {
    package let ref: LLVMValueRef

    package init(_ ref: LLVMValueRef) {
        self.ref = ref
    }

    public var anyValue: AnyValue { AnyValue(ref) }

    /// The pointer to the variable's value, which code loads it through.
    public var pointer: PointerValue { PointerValue(ref) }

    /// Makes the variable a constant, which no code may store to.
    public func setConstant() {
        LLVMSetGlobalConstant(ref, 1)
    }

    /// Marks the variable's address as one no code compares, so that LLVM may merge it with an equal constant.
    public func setUnnamedAddress() {
        LLVMSetUnnamedAddress(ref, LLVMGlobalUnnamedAddr)
    }
}
