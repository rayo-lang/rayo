package import CLLVM

/// An LLVM integer value of `Width`.
public struct IntValue<Width: IntegerWidth>: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    /// Takes `ref` as an integer of `Width`, which it must be.
    package init(unchecked ref: LLVMValueRef) {
        self.ref = ref
    }

    /// Returns `value` as an integer of `Width`, or nil where it is of another type.
    public init?(_ value: some ValueHandle) {
        // A value of another type, or an integer of another width, isn't one of these.
        guard value.anyValue.type.integerWidth == Width.bitWidth else { return nil }
        self.init(unchecked: value.anyValue.ref)
    }

    public var anyValue: AnyValue { AnyValue(ref) }
}
