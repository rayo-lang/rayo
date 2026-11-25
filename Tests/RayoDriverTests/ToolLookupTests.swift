import Foundation
import Testing
import RayoDriver
import RayoLLVMInstall
import ToolStandIn

/// The name of the host's LLD, which `rayo` runs from beside itself where it is there.
#if canImport(Darwin)
private let hostLLD = "ld64.lld"
#elseif os(Linux)
private let hostLLD = "ld.lld"
#elseif os(Windows)
private let hostLLD = "lld-link"
#endif

/// What a build that compiles and links gives.
private let built = CommandResult(exitCode: 0, output: "", errors: "")

/// Makes `directory` a toolchain that holds a copy of the built `rayo`, and a `rayoc` that makes the file at `ran`,
/// then compiles as the built `rayoc` does. Returns the copy of `rayo`.
private func toolchain(in directory: URL, rayocRan ran: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let rayo = directory.appendingPathComponent(Executable.fileName("rayo"))
    try FileManager.default.copyItem(at: builtProduct("rayo"), to: rayo)
    _ = try install(ToolStandIn([.touch(ran)], then: .handOff(toToolAt: builtProduct("rayoc"))),
                    as: "rayoc", in: directory)
    return rayo
}

/// Installs the tool `name` in `directory`, which makes the file at `ran`, then hands what it is given to `tool`.
private func installRecording(_ tool: URL, as name: String, in directory: URL, ran: URL) throws {
    _ = try install(ToolStandIn([.touch(ran)], then: .handOff(toToolAt: tool)), as: name, in: directory)
}

struct ToolLookupTests {
    @Test(arguments: [(true, true), (true, false), (false, true), (false, false)])
    func `build runs each of clang and LLD from beside rayo where it is there, and else from the LLVM install`(
        clangBeside: Bool, lldBeside: Bool,
    ) throws {
        try withTemporaryDirectory { directory in
            let bin = directory.appendingPathComponent("toolchain", isDirectory: true)
            let copy = try toolchain(in: bin, rayocRan: directory.appendingPathComponent("rayoc-ran"))
            let clangRan = directory.appendingPathComponent("clang-ran")
            let lldRan = directory.appendingPathComponent("lld-ran")
            if clangBeside { try installRecording(LinkTools.installed.clang, as: "clang", in: bin, ran: clangRan) }
            if lldBeside { try installRecording(LinkTools.installed.lld, as: hostLLD, in: bin, ran: lldRan) }
            _ = try save("func main() { print(42) }", as: "answer.rayo", in: directory)

            #expect(rayo(["build", "answer.rayo"], in: directory, running: copy) == built)
            #expect(FileManager.default.fileExists(atPath: clangRan.path) == clangBeside)
            #expect(FileManager.default.fileExists(atPath: lldRan.path) == lldBeside)
        }
    }

    // Windows makes symbolic links only for administrators and in developer mode.
    #if !os(Windows)
    @Test func `a rayo reached through a symbolic link runs the tools beside the file the link names`() throws {
        try withTemporaryDirectory { directory in
            let bin = directory.appendingPathComponent("toolchain", isDirectory: true)
            let rayocRan = directory.appendingPathComponent("rayoc-ran")
            let copy = try toolchain(in: bin, rayocRan: rayocRan)
            let clangRan = directory.appendingPathComponent("clang-ran")
            let lldRan = directory.appendingPathComponent("lld-ran")
            try installRecording(LinkTools.installed.clang, as: "clang", in: bin, ran: clangRan)
            try installRecording(LinkTools.installed.lld, as: hostLLD, in: bin, ran: lldRan)
            let links = directory.appendingPathComponent("links", isDirectory: true)
            try FileManager.default.createDirectory(at: links, withIntermediateDirectories: true)
            let link = links.appendingPathComponent("rayo")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: copy)
            _ = try save("func main() { print(42) }", as: "answer.rayo", in: directory)

            #expect(rayo(["build", "answer.rayo"], in: directory, running: link) == built)
            for ran in [rayocRan, clangRan, lldRan] { #expect(FileManager.default.fileExists(atPath: ran.path)) }
        }
    }
    #endif

    @Test func `a link that finds clang in none of its places names each place once`() throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let first = directory.appendingPathComponent("first")
            let second = directory.appendingPathComponent("second")
            let linkTools = [first, second, first].map { LinkTools(clang: $0, lld: LinkTools.installed.lld) }
            #expect(Driver.run(["build", source], compiler: builtProduct("rayoc"), linkTools: linkTools) ==
                CommandResult(exitCode: 1, output: "", errors: """
                    rayo: can't find clang at '\(first.path)' or '\(second.path)'

                    """))
        }
    }

    @Test func `a link that finds LLD in none of its places names each place once`() throws {
        try withTemporaryDirectory { directory in
            let source = try save("func main() {}", as: "main.rayo", in: directory)
            let first = directory.appendingPathComponent("first")
            let second = directory.appendingPathComponent("second")
            let linkTools = [first, second, first].map { LinkTools(clang: LinkTools.installed.clang, lld: $0) }
            #expect(Driver.run(["build", source], compiler: builtProduct("rayoc"), linkTools: linkTools) ==
                CommandResult(exitCode: 1, output: "", errors: """
                    rayo: can't find LLD at '\(first.path)' or '\(second.path)': install LLD 23, run \
                    'swift package purge-cache' and build rayo again, or link with --linker=platform

                    """))
        }
    }
}
