package import CLLVM

/// An LLVM type of any kind.
public struct AnyType: TypeHandle, Equatable {
    package let ref: LLVMTypeRef

    package init(_ ref: LLVMTypeRef) {
        self.ref = ref
    }

    public var anyType: AnyType { self }

    /// The type as LLVM IR writes it, such as `i64`, or a named struct's definition.
    public var text: String { takeMessage(LLVMPrintTypeToString(ref)) }

    /// Whether this is the type of a function's result when it returns nothing.
    public var isVoid: Bool { LLVMGetTypeKind(ref) == LLVMVoidTypeKind }

    /// The width of this type in bits, where it is an integer type, or nil where it isn't.
    public var integerWidth: UInt32? {
        LLVMGetTypeKind(ref) == LLVMIntegerTypeKind ? LLVMGetIntTypeWidth(ref) : nil
    }
}
