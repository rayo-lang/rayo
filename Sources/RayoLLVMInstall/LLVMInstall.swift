internal import CLLVMInstall

/// The LLVM install that Rayo's tools were built against, whose clang and LLD link the programs `rayoc` compiles.
public enum LLVMInstall {
    public static let majorVersion = Int(RayoLLVMMajorVersion)

    /// The directory that holds LLVM's tools, clang among them.
    public static let toolDirectory = String(cString: RayoLLVMToolDirectory)

    /// The directory that holds LLD, which some package managers install apart from LLVM.
    public static let lldDirectory = String(cString: RayoLLDDirectory)
}
