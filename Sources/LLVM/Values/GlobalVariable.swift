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

    /// Whether no code may store to the variable.
    public var isConstant: Bool {
        get { LLVMIsGlobalConstant(ref) != 0 }
        nonmutating set { LLVMSetGlobalConstant(ref, newValue ? 1 : 0) }
    }

    /// Whether no code compares the variable's address, so LLVM may merge it with an equal constant.
    public var hasUnnamedAddress: Bool {
        get { LLVMGetUnnamedAddress(ref) == LLVMGlobalUnnamedAddr }
        nonmutating set { LLVMSetUnnamedAddress(ref, newValue ? LLVMGlobalUnnamedAddr : LLVMNoUnnamedAddr) }
    }
}
