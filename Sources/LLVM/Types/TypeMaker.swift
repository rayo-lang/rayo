internal import CLLVM

/// Makes types in an LLVM context, and keeps the context alive while any copy of it is held. Keep one where types
/// are made after the `Context` is out of reach.
public struct TypeMaker {
    private let context: OwnedContext

    init(_ context: OwnedContext) {
        self.context = context
    }

    /// Makes a struct type named `name`, which has no fields until it is given them.
    public func makeStructType(named name: String) -> StructType {
        StructType(LLVMStructCreateNamed(context.ref, name))
    }

    public func arrayType(of element: some TypeHandle, count: Int) -> AnyType {
        AnyType(LLVMArrayType2(element.anyType.ref, UInt64(count)))
    }
}
