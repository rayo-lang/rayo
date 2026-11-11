enum BuildMode: String {
    case debug = "--debug"
    case release = "--release"

    /// Whether integer overflow panics, where it would otherwise wrap.
    var checksOverflow: Bool { self == .debug }

    /// Whether LLVM optimises the program.
    var optimizes: Bool { self == .release }
}
