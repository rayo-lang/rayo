import Foundation
import Testing
import RayoIR
import RayoLLVM
import RayoSema
import RayoSyntax

struct ObjectCodeTests {
    @Test(arguments: Build.allCases)
    func `a program compiles to an object file for the host, in debug and in release`(build: Build) throws {
        let objectCode = try compile(printing(.use(.constant(.int(42)))), for: build)
        let headers = try llvmTool("llvm-readobj", ["--file-headers"], on: objectCode)
        #expect(headers.contains("Format: \(hostFormat)"))
        #expect(headers.contains("Arch: \(hostArchitecture)\n"))
    }

    @Test(.enabled(if: !llvmAssertsOnInvalidIR), arguments: Build.allCases)
    func `IR that LLVM rejects is an internal error, not a crash`(build: Build) {
        let addsBoolToInt = function(locals: [.bool, .int, .int], [
            BasicBlock(
                statements: [statement(storingIn: 2, .binary(.add, read(0), read(1)))],
                terminator: .return(nil),
            ),
        ])
        let branchesOnInt = function(locals: [.int], [
            BasicBlock(
                statements: [],
                terminator: .branch(read(0), then: BlockID(index: 1), otherwise: BlockID(index: 1)),
            ),
            BasicBlock(statements: [], terminator: .return(nil)),
        ])
        for program in [addsBoolToInt, branchesOnInt] {
            let error = #expect(throws: LLVMError.self) { try compile(program, for: build) }
            #expect(error?.message.hasPrefix("LLVM rejected the module it was given:\n") == true)
        }
    }

    @Test(arguments: Build.allCases)
    func `a move of a local compiles to the code that a read of it does, in debug and in release`(
        build: Build,
    ) throws {
        /// A program that stores 42 in one local, then `taken` in another, and prints that one.
        func handingOn(_ taken: Operand) -> IRProgram {
            function(locals: [.int, .int], [
                BasicBlock(statements: [
                    statement(storingIn: 0, .use(.constant(.int(42)))),
                    statement(storingIn: 1, .use(taken)),
                    statement(printing: read(1)),
                ], terminator: .return(nil)),
            ])
        }
        #expect(try compile(handingOn(move(0)), for: build) == compile(handingOn(read(0)), for: build))
    }

    @Test(arguments: Build.allCases)
    func `a declaration compiles to no code, in debug and in release`(build: Build) throws {
        let declared = function(locals: [.int], [
            BasicBlock(statements: [.declare(LocalID(index: 0))], terminator: .return(nil)),
        ])
        let empty = function(locals: [.int], [BasicBlock(statements: [], terminator: .return(nil))])
        #expect(try compile(declared, for: build) == compile(empty, for: build))
    }

    @Test func `a debug build checks integer arithmetic for overflow, and a release build emits no check`() throws {
        let overflows = printing(.binary(.add, .constant(.int(.max)), .constant(.int(1))))
        let report = Array("panic: integer overflow".utf8)
        #expect(try compile(overflows, for: .debug).firstRange(of: report) != nil)
        #expect(try compile(overflows, for: .release).firstRange(of: report) == nil)
    }
}
