package import CLLVM

/// A basic block of a function, which a builder adds instructions to and a branch goes to. It is valid while its
/// function's module lives, and not once the module is linked into another.
public struct BasicBlock: Equatable {
    package let ref: LLVMBasicBlockRef

    package init(_ ref: LLVMBasicBlockRef) {
        self.ref = ref
    }
}
