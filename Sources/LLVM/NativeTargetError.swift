internal import CLLVM

/// Why LLVM can't compile for the host, or nil when it can. Initialising it registers the host's target, once per
/// process, since registration isn't safe to run on two threads at once.
let nativeTargetError: String? = {
    if LLVMInitializeNativeTarget() != 0 { return "LLVM can't target this host" }
    if LLVMInitializeNativeAsmPrinter() != 0 { return "LLVM can't write object code for this host" }
    return nil
}()
