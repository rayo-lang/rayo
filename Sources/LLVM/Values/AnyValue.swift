package import CLLVM

/// An LLVM value of any type.
public struct AnyValue: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    package init(_ ref: LLVMValueRef) {
        self.ref = ref
    }

    public var anyValue: AnyValue { self }

    public var type: AnyType { AnyType(LLVMTypeOf(ref)) }

    /// The value as LLVM IR writes it: an instruction, a constant, or a whole function's definition.
    public var text: String { takeMessage(LLVMPrintValueToString(ref)) }

    /// Whether this is LLVM's `undef` or `poison`, a value of no particular bits.
    public var isUndefined: Bool { LLVMIsUndef(ref) != 0 }
}
