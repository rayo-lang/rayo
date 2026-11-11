/// A build's mode, which turns the diagnostic checks on and optimisation off in a debug build, and the other way
/// round in a release one.
enum BuildMode: String {
    case debug = "--debug"
    case release = "--release"
}
