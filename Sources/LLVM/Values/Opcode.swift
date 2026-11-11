package import CLLVM

/// What an instruction does, such as allocate a stack slot or return.
public struct Opcode: Equatable, Sendable {
    private let opcode: LLVMOpcode

    package init(_ opcode: LLVMOpcode) {
        self.opcode = opcode
    }

    /// `alloca`.
    public static let allocate = Opcode(LLVMAlloca)
    public static let load = Opcode(LLVMLoad)
    public static let store = Opcode(LLVMStore)
    /// `ret`.
    public static let `return` = Opcode(LLVMRet)
}
