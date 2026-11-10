/// The runtime that every program links: the C entry point, and the functions a program calls to print and to
/// report a panic. `rayoc` embeds the runtime's LLVM IR, so it needs no files beside it to compile a program.
public enum ProgramRuntime {
    /// The exit code of a program that panics. The runtime reads it from the program it is linked into, so the code
    /// a panic exits with is always the one `rayoc` reports.
    public static let panicExitCode: Int32 = 101

    /// The runtime's LLVM IR files, in the syntax of the LLVM release `rayoc` builds against.
    public static let files: [File] = [
        File(name: "entry.ll", llvmIR: PackageResources.entry_ll),
        File(name: "print.ll", llvmIR: PackageResources.print_ll),
        File(name: "panic.ll", llvmIR: PackageResources.panic_ll),
    ]

    /// One of the runtime's files, and the LLVM IR it holds.
    public struct File: Sendable {
        public let name: String
        public let llvmIR: [UInt8]
    }
}
