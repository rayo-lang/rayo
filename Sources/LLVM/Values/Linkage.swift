internal import CLLVM

/// Which code sees a function's or a global's name once its module is linked.
public enum Linkage: Equatable {
    /// Only its own module, which optimisation may drop it from where nothing uses it.
    case `internal`
    /// Only its own module, as `internal`, and the object code's symbol table doesn't name it.
    case `private`

    var llvmLinkage: LLVMLinkage {
        switch self {
        case .internal: LLVMInternalLinkage
        case .private: LLVMPrivateLinkage
        }
    }
}
