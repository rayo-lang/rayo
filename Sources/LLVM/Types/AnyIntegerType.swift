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

    public var bitWidth: Int { Int(LLVMGetIntTypeWidth(ref)) }

    /// The constant of this type that holds `value`'s low bits, as many as the type is wide, of a width up to 128.
    public func constant(_ value: Int128) -> AnyIntValue {
        // LLVM reads the bits as 64-bit words, the low word first.
        let bits = UInt128(bitPattern: value)
        let words = [UInt64(truncatingIfNeeded: bits), UInt64(truncatingIfNeeded: bits >> 64)]
        return AnyIntValue(unchecked: words.withUnsafeBufferPointer {
            LLVMConstIntOfArbitraryPrecision(ref, UInt32($0.count), $0.baseAddress)
        })
    }
}
