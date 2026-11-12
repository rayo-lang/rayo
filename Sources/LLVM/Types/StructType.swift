package import CLLVM

/// A named LLVM struct type, which has no fields until it is given them.
public struct StructType: TypeHandle, Equatable {
    package let ref: LLVMTypeRef

    package init(_ ref: LLVMTypeRef) {
        self.ref = ref
    }

    public var anyType: AnyType { AnyType(ref) }

    /// The value of the struct whose fields hold no particular bits.
    public var poison: AggregateValue { AggregateValue(unchecked: LLVMGetPoison(ref)) }

    /// Gives the struct `fields`, in order. A packed struct has no padding between its fields.
    public func setFields(_ fields: [any TypeHandle], packed: Bool) {
        var fields = fields.map { Optional($0.anyType.ref) }
        LLVMStructSetBody(ref, &fields, UInt32(fields.count), packed ? 1 : 0)
    }
}
