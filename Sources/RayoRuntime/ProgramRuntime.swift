/// The runtime that every program links: the C entry point, and the functions a program calls to print and to
/// report a panic. It is written in LLVM IR by hand until `rayoc` can compile a runtime written in Rayo, and
/// `rayoc` embeds it, so it needs no files beside it to compile a program.
public enum ProgramRuntime {
    /// The exit code of a program that panics. `rayoc` defines it in each program as `rayo.panic_exit_code`, which
    /// `panic.ll` reads, so the runtime can't exit with one code while `rayoc` reports another.
    public static let panicExitCode: Int32 = 101

    /// The runtime's LLVM IR files for the host, in the syntax of the LLVM release `rayoc` builds against.
    public static let files: [File] = [
        File(name: "entry.ll", llvmIR: PackageResources.entry_ll),
        File(name: "print.ll", llvmIR: PackageResources.print_ll),
        File(name: "panic.ll", llvmIR: PackageResources.panic_ll),
        host,
    ]

    // The file that readies a run and writes to standard error the way the host's C runtime does.
    #if os(Windows)
    private static let host = File(name: "host-windows.ll", llvmIR: PackageResources.host_windows_ll)
    #else
    private static let host = File(name: "host-posix.ll", llvmIR: PackageResources.host_posix_ll)
    #endif

    public struct File: Sendable {
        public let name: String
        public let llvmIR: [UInt8]
    }
}
