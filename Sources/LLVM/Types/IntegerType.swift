package import CLLVM

/// An LLVM integer type of `Width`.
public struct IntegerType<Width: IntegerWidth>: TypeHandle, Equatable {
    package let ref: LLVMTypeRef

    package init(_ ref: LLVMTypeRef) {
        self.ref = ref
    }

    public var anyType: AnyType { AnyType(ref) }

    /// The constant of this type that holds `value`'s low bits, as many as the type is wide.
    public func constant(_ value: Int64) -> IntValue<Width> {
        IntValue(unchecked: LLVMConstInt(ref, UInt64(bitPattern: value), 1))
    }
}
