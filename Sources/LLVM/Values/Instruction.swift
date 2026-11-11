package import CLLVM

/// An instruction of a basic block.
public struct Instruction: ValueHandle, Equatable {
    package let ref: LLVMValueRef

    package init(_ ref: LLVMValueRef) {
        self.ref = ref
    }

    public var anyValue: AnyValue { AnyValue(ref) }

    public var opcode: Opcode { Opcode(LLVMGetInstructionOpcode(ref)) }

    /// The alignment, in bytes, of the memory a stack slot, a load or a store reaches, or nil for any other
    /// instruction.
    public var alignment: Int? {
        // LLVM keeps an alignment only on the instructions that reach memory.
        guard [.allocate, .load, .store].contains(opcode) else { return nil }
        return Int(LLVMGetAlignment(ref))
    }

    /// The type of the value a stack slot holds, or nil where the instruction allocates none.
    public var allocatedType: AnyType? {
        opcode == .allocate ? AnyType(LLVMGetAllocatedType(ref)) : nil
    }

    /// The operand at `index`, which must be one of the instruction's.
    public func operand(at index: Int) -> AnyValue {
        AnyValue(LLVMGetOperand(ref, UInt32(index)))
    }
}
