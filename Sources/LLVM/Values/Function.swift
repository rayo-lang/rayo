package import CLLVM

/// An LLVM function, declared or defined in a module, with the type that a call of it names.
public struct Function: ValueHandle, GlobalValue, Equatable {
    package let ref: LLVMValueRef
    public let type: FunctionType

    package init(_ ref: LLVMValueRef, type: FunctionType) {
        self.ref = ref
        self.type = type
    }

    /// Takes `ref`, a function of some module, with the type it is declared with.
    package init(_ ref: LLVMValueRef) {
        self.init(ref, type: FunctionType(LLVMGlobalGetValueType(ref)))
    }

    public var anyValue: AnyValue { AnyValue(ref) }

    /// The argument a call passes in the parameter at `index`.
    public func parameter(at index: Int) -> AnyValue {
        AnyValue(LLVMGetParam(ref, UInt32(index)))
    }

    /// The function as LLVM IR writes it: its definition, or its declaration where it has no body.
    public var text: String { anyValue.text }
}
