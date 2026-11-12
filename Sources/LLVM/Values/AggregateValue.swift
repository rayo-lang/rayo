package import CLLVM

/// An LLVM struct or array value, whose fields are read by their index.
public struct AggregateValue: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    /// Takes `ref` as an aggregate, which it must be.
    package init(unchecked ref: LLVMValueRef) {
        self.ref = ref
    }

    /// Returns `value` as an aggregate, or nil where it is neither a struct nor an array.
    public init?(_ value: some ValueHandle) {
        // A value of any other kind has no fields.
        let kind = LLVMGetTypeKind(value.anyValue.type.ref)
        guard kind == LLVMStructTypeKind || kind == LLVMArrayTypeKind else { return nil }
        ref = value.anyValue.ref
    }

    public var anyValue: AnyValue { AnyValue(ref) }
}
