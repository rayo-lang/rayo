extension TargetMachine {
    /// The most bytes LLVM puts in one function's fixed frame for this machine, or nil where it puts any number.
    /// Windows on arm64 tells its unwinder a frame's size in 24 bits of 16-byte units, so LLVM ends the whole process,
    /// with no error to catch, at a fixed frame of 256 MiB or more. A slot that `Builder.allocateOutsideFrame` makes
    /// takes no room in the fixed frame.
    public var largestFrame: Int? {
        let isArm64 = triple.hasPrefix("aarch64") || triple.hasPrefix("arm64")
        return isArm64 && compilesForWindows ? (1 << 28) - 1 : nil
    }
}
