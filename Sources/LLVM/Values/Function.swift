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

    /// The function's blocks, in order, the entry block first. A function the module only declares has none.
    public var blocks: [BasicBlock] {
        var blocks: [BasicBlock] = []
        var next = LLVMGetFirstBasicBlock(ref)
        while let block = next {
            blocks.append(BasicBlock(block))
            next = LLVMGetNextBasicBlock(block)
        }
        return blocks
    }

    /// Gives the function `attributes`, beside those it carries already.
    public func add(_ attributes: [FunctionAttribute]) {
        let context = LLVMGetModuleContext(LLVMGetGlobalParent(ref))!
        for attribute in attributes {
            LLVMAddAttributeAtIndex(ref, FunctionAttribute.functionIndex, attribute.ref(in: context))
        }
    }

    /// Whether the function carries `attribute`.
    public func carries(_ attribute: FunctionAttribute) -> Bool {
        attribute.isCarried(by: ref)
    }

    /// The function as LLVM IR writes it: its definition, or its declaration where it has no body.
    public var text: String { anyValue.text }
}
