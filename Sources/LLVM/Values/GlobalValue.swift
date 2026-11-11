internal import CLLVM

/// A function or a global variable of a module, which code outside the module may see by its name.
public protocol GlobalValue: ValueHandle {}

extension GlobalValue {
    public var name: String {
        var length = 0
        let name = LLVMGetValueName2(anyValue.ref, &length)!
        return String(decoding: UnsafeRawBufferPointer(start: name, count: length), as: UTF8.self)
    }

    /// Whether the module only declares the value, and some other module defines it.
    public var isDeclaration: Bool { LLVMIsDeclaration(anyValue.ref) != 0 }

    /// Sets which code sees the value's name once the module is linked.
    public func setLinkage(_ linkage: Linkage) {
        LLVMSetLinkage(anyValue.ref, linkage.llvmLinkage)
    }
}
