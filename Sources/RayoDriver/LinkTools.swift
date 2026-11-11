import Foundation
import RayoLLVMInstall

/// The clang that drives the link of a program, and the LLD it links with unless the platform's linker is asked for.
public struct LinkTools: Sendable {
    public var clang: URL
    /// The LLD for the host's object file format: `ld64.lld` for Mach-O, and `ld.lld` for ELF.
    public var lld: URL

    public init(clang: URL, lld: URL) {
        self.clang = clang
        self.lld = lld
    }

    /// The clang and LLD of the LLVM install that `rayo` was built against.
    public static let installed = LinkTools(
        clang: URL(fileURLWithPath: LLVMInstall.toolDirectory).appendingPathComponent(executableName("clang")),
        lld: URL(fileURLWithPath: LLVMInstall.lldDirectory).appendingPathComponent(hostLLD))

    #if canImport(Darwin)
    private static let hostLLD = "ld64.lld"
    #elseif os(Linux)
    private static let hostLLD = "ld.lld"
    #elseif os(Windows)
    private static let hostLLD = "lld-link.exe"
    #else
    #error("rayo links with LLD only on macOS, Linux and Windows")
    #endif
}
