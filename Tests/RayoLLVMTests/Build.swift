/// A build `rayoc` makes of a program: how it emits its code, and whether it optimises it.
enum Build: CaseIterable {
    /// A debug build: overflow panics, and the module isn't optimised.
    case debug
    /// A release build: overflow wraps, and the module is optimised as the compiler optimises a program's.
    case release
}
