import Foundation

/// Links object code into an executable at `executable`.
struct Link: CompilationStep {
    var toolchain: Toolchain
    var executable: URL

    func run(_ objectCode: [UInt8]) throws(CompilationError) {
        try toolchain.link(objectCode, to: executable)
    }
}
