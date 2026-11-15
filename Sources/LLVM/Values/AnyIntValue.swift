package import CLLVM

/// An LLVM integer value whose width the value carries, rather than its Swift type, for an integer whose width is
/// known only once a program says what its types are.
public struct AnyIntValue: IntegerHandle, Equatable {
    package let ref: LLVMValueRef

    /// Takes `ref` as an integer, which it must be.
    package init(unchecked ref: LLVMValueRef) {
        self.ref = ref
    }

    /// Returns `value` as an integer, of whatever width it has, or nil where it is of another type.
    public init?(_ value: some ValueHandle) {
        guard value.anyValue.type.integerWidth != nil else { return nil }
        self.init(unchecked: value.anyValue.ref)
    }

    public var anyValue: AnyValue { AnyValue(ref) }

    public var bitWidth: Int { Int(LLVMGetIntTypeWidth(LLVMTypeOf(ref))) }
}
