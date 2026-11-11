package import CLLVM

/// A basic block of a function, which a builder adds instructions to and a branch goes to. It is valid while its
/// function's module lives, and not once the module is linked into another or handed to a JIT.
public struct BasicBlock: Equatable {
    package let ref: LLVMBasicBlockRef

    package init(_ ref: LLVMBasicBlockRef) {
        self.ref = ref
    }

    /// The block's instructions, in order.
    public var instructions: [Instruction] {
        var instructions: [Instruction] = []
        var next = LLVMGetFirstInstruction(ref)
        while let instruction = next {
            instructions.append(Instruction(instruction))
            next = LLVMGetNextInstruction(instruction)
        }
        return instructions
    }

    /// The instruction that ends the block, or nil where nothing ends it yet.
    public var terminator: Instruction? {
        LLVMGetBasicBlockTerminator(ref).map(Instruction.init)
    }
}
