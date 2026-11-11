/// How a build of a program emits its code, and whether it optimises it.
enum Build: Equatable {
    /// A debug build's: overflow panics, and the module isn't optimised.
    case debug
    /// A release build's: overflow wraps, and the module is optimised as the compiler optimises a program's.
    /// Only the runtime is left out, so that the stand-in for its panic catches a panic.
    case release
}
