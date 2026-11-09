import CLLVM
import Foundation
import RayoIR
import RayoLLVM
import RayoSema
import RayoSource
import Testing

/// Compiles `program` the way a debug or a release build does.
func compile(_ program: IRProgram, debug: Bool) throws(LLVMError) -> [UInt8] {
    try LLVMEmitter.objectCode(for: program, sourcePath: "main.rayo", checksOverflow: debug, optimizes: !debug)
}

/// A program whose `main` holds `locals` and is made of `blocks`.
func function(locals: [RayoType], _ blocks: [BasicBlock]) -> IRProgram {
    IRProgram(main: IRFunction(locals: locals, blocks: blocks))
}

/// A program that prints what `value` computes.
func printing(_ value: Rvalue) -> IRProgram {
    function(locals: [.int], [
        BasicBlock(statements: [
            statement(storingIn: 0, value),
            Statement(destination: nil, value: .call(.printInt, arguments: [.local(LocalID(index: 0))]), range: nowhere),
        ], terminator: .return),
    ])
}

func statement(storingIn local: Int, _ value: Rvalue) -> Statement {
    Statement(destination: LocalID(index: local), value: value, range: nowhere)
}

/// The range of an operation no source file wrote.
let nowhere = SourceRange(SourceLocation(line: 1, column: 1, offset: 0), SourceLocation(line: 1, column: 1, offset: 0))

/// What `tool`, from the LLVM install `rayoc` builds against, writes to its standard output when it reads
/// `objectCode` from a file named after `arguments`.
func llvmTool(_ tool: String, _ arguments: [String], on objectCode: [UInt8]) throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rayo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let object = directory.appendingPathComponent("main.o")
    try Data(objectCode).write(to: object)
    return try llvmTool(tool, arguments + [object.path])
}

/// What `tool`, from the LLVM install `rayoc` builds against, writes to its standard output given `arguments`.
func llvmTool(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: String(cString: RayoLLVMToolDirectory)).appendingPathComponent(tool)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()
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
