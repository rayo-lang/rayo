/// The linker that clang links a program with.
enum Linker: String {
    /// LLD, which links the same way on every platform.
    case lld
    /// The platform's own: Apple's `ld` on macOS, and the system `ld` on Linux.
    case platform
}
