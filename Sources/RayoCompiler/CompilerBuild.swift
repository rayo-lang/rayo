/// How `rayoc` itself is built, which decides how much of its stages' IR it checks. It is apart from the build mode
/// `rayoc` compiles a program in.
enum CompilerBuild: Sendable {
    case debug
    case release

    /// The build of this `rayoc`.
    static var current: CompilerBuild {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}
