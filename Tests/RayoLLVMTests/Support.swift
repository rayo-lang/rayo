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

/// A program whose `main` holds temporaries of `locals`' types and is made of `blocks`.
func function(locals: [RayoType], _ blocks: [BasicBlock]) -> IRProgram {
    IRProgram(functions: [mainFunction(locals: locals, blocks)], main: FunctionID(index: 0))
}

/// A `main` that holds temporaries of `locals`' types and is made of `blocks`.
func mainFunction(locals: [RayoType], _ blocks: [BasicBlock]) -> IRFunction {
    IRFunction(
        name: "main()", parameterCount: 0, result: .void, locals: locals.map(IRLocal.temporary), blocks: blocks,
    )
}

/// An operand that reads the local `index`.
func read(_ index: Int) -> Operand {
    .read(Place(local: LocalID(index: index), range: nowhere))
}

/// An operand that moves the local `index`'s value out of it.
func move(_ index: Int) -> Operand {
    .move(Place(local: LocalID(index: index), range: nowhere))
}

/// A program that prints what `value` computes.
func printing(_ value: Rvalue) -> IRProgram {
    function(locals: [.int], [
        BasicBlock(statements: [
            statement(storingIn: 0, value),
            statement(printing: read(0)),
        ], terminator: .return(nil)),
    ])
}

func statement(storingIn local: Int, _ value: Rvalue) -> Statement {
    .compute(destination: Place(local: LocalID(index: local), range: nowhere), value: value, range: nowhere)
}

/// A statement that prints the Int `operand` holds.
func statement(printing operand: Operand) -> Statement {
    .compute(destination: nil, value: .call(.printInt, arguments: [operand]), range: nowhere)
}

/// The range of an operation no source file wrote.
let nowhere = SourceRange(SourceLocation(line: 1, column: 1, offset: 0), SourceLocation(line: 1, column: 1, offset: 0))

/// The source range of every operator the operator tests emit.
let operatorRange = SourceRange(SourceLocation(line: 3, column: 7, offset: 20),
                                SourceLocation(line: 3, column: 12, offset: 25))

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
    process.executableURL = URL(fileURLWithPath: LLVMInstall.toolDirectory).appendingPathComponent(tool)
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
