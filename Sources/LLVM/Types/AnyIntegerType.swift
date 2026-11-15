package import CLLVM

/// An LLVM integer type whose width the type carries, rather than its Swift type, for an integer whose width is known
/// only once a program says what its types are.
public struct AnyIntegerType: IntegerTypeHandle, Equatable {
    public typealias Value = AnyIntValue

    package let ref: LLVMTypeRef

    package init(_ ref: LLVMTypeRef) {
        self.ref = ref
    }

    public var anyType: AnyType { AnyType(ref) }

    /// The type's width in bits.
    public var bitWidth: Int { Int(LLVMGetIntTypeWidth(ref)) }

    /// The constant of this type that holds `value`'s low bits, as many as the type is wide.
    public func constant(_ value: Int64) -> AnyIntValue {
        AnyIntValue(unchecked: LLVMConstInt(ref, UInt64(bitPattern: value), 1))
    }
}
