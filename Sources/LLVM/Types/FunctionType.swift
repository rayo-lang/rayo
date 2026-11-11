package import CLLVM

/// The LLVM type of a function: what it returns, and the types of its parameters.
public struct FunctionType: TypeHandle, Equatable {
    package let ref: LLVMTypeRef

    package init(_ ref: LLVMTypeRef) {
        self.ref = ref
    }

    public var anyType: AnyType { AnyType(ref) }

    public var result: AnyType { AnyType(LLVMGetReturnType(ref)) }

    public var parameters: [AnyType] {
        var parameters = [LLVMTypeRef?](repeating: nil, count: Int(LLVMCountParamTypes(ref)))
        LLVMGetParamTypes(ref, &parameters)
        return parameters.map { AnyType($0!) }
    }
}
