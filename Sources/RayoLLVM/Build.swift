/// The build mode `rayoc` compiles a program in, which decides how the program's code is emitted and optimised.
package enum Build: CaseIterable, Sendable {
    case debug
    case release

    /// Whether integer overflow panics, where otherwise it wraps.
    var checksOverflow: Bool { self == .debug }

    /// Whether LLVM optimises the program.
    var optimizes: Bool { self == .release }
}
