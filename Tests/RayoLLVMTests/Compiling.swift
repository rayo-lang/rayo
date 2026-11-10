import Foundation
import RayoIR
import RayoLLVM
import Testing

/// Compiles `program` the way `build` does.
func compile(_ program: IRProgram, for build: Build) throws(LLVMError) -> [UInt8] {
    try LLVMEmitter.objectCode(
        for: program, sourcePath: "main.rayo", checksOverflow: build == .debug, optimizes: build == .release,
    )
}

/// What `tool`, from the LLVM install `rayoc` builds against, writes to its standard output when it reads
/// `objectCode` from a file named after `arguments`.
func llvmTool(_ tool: String, _ arguments: [String], on objectCode: [UInt8]) throws -> String {
    // Write the object code to a file in a directory of its own, which goes once the tool has read it.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let object = directory.appendingPathComponent("main.o")
    try Data(objectCode).write(to: object)

    return try llvmTool(tool, arguments + [object.path])
}

/// What `tool`, from the LLVM install `rayoc` builds against, writes to its standard output given `arguments`.
func llvmTool(_ tool: String, _ arguments: [String]) throws -> String {
    // Run the tool with its standard output on a pipe.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: LLVMInstall.toolDirectory).appendingPathComponent(tool)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()

    // Read all it writes before waiting for it to exit, so that a full pipe can't stall it.
    let written = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(tool) \(arguments.joined(separator: " ")) failed")
    return written
}

/// Whether the LLVM install checks its own invariants, and so stops the process on IR it should only reject.
let llvmAssertsOnInvalidIR = (try? llvmTool("llvm-config", ["--assertion-mode"])) != "OFF\n"

#if os(macOS)
let hostFormat = "Mach-O"
#elseif os(Linux)
let hostFormat = "elf64-"
#endif

#if arch(arm64)
let hostArchitecture = "aarch64"
#elseif arch(x86_64)
let hostArchitecture = "x86_64"
#endif
