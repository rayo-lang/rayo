internal import CLLVM

/// The LLVM install that `rayoc` was built against, whose clang and LLD link the programs it compiles.
public enum LLVMInstall {
    public static let majorVersion = Int(LLVM_VERSION_MAJOR)

    /// The directory that holds LLVM's tools, clang among them.
    public static let toolDirectory = String(cString: RayoLLVMToolDirectory)

    /// The directory that holds LLD, which some package managers install apart from LLVM.
    public static let lldDirectory = String(cString: RayoLLDDirectory)
}
