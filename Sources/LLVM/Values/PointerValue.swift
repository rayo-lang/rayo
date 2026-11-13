package import CLLVM

/// An LLVM pointer: to a stack slot, to a global, or one a function is passed.
public struct PointerValue: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    package init(_ ref: LLVMValueRef) {
        self.ref = ref
    }

    /// Returns `value` as a pointer, or nil where it is of another type.
    public init?(_ value: some ValueHandle) {
        guard LLVMGetTypeKind(value.anyValue.type.ref) == LLVMPointerTypeKind else { return nil }
        ref = value.anyValue.ref
    }

    public var anyValue: AnyValue { AnyValue(ref) }
}
