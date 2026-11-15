/// A handle to an LLVM integer type, which names the kind of handle that holds the type's values.
public protocol IntegerTypeHandle: TypeHandle {
    associatedtype Value: IntegerHandle

    /// The type's width in bits.
    var bitWidth: Int { get }
}
