import Foundation
import Testing
import RayoIR
import RayoLLVM
import RayoSema
import RayoSyntax

struct ObjectCodeTests {
    @Test("a program compiles to an object file for the host, in debug and in release", arguments: [true, false])
    func hostObject(debug: Bool) throws {
        let headers = try llvmTool("llvm-readobj", ["--file-headers"], on: compile(printing(.use(.constant(.int(42)))),
                                                                                    debug: debug))
        #expect(headers.contains("Format: \(hostFormat)"))
        #expect(headers.contains("Arch: \(hostArchitecture)\n"))
    }

    @Test("IR that LLVM rejects is an internal error, not a crash", .enabled(if: !llvmAssertsOnInvalidIR),
          arguments: [true, false])
    func rejectedIR(debug: Bool) throws {
        let addsBoolToInt = function(locals: [.bool, .int, .int], [
            BasicBlock(statements: [statement(storingIn: 2, .binary(.add, read(0), read(1)))],
                       terminator: .return(nil)),
        ])
        let branchesOnInt = function(locals: [.int], [
            BasicBlock(statements: [], terminator: .branch(read(0), then: BlockID(index: 1),
                                                           otherwise: BlockID(index: 1))),
            BasicBlock(statements: [], terminator: .return(nil)),
        ])
        for program in [addsBoolToInt, branchesOnInt] {
            do {
                _ = try compile(program, debug: debug)
                Issue.record("LLVM compiled IR it should have rejected")
            } catch {
                #expect(error.message.hasPrefix("LLVM rejected the module it was given:\n"))
            }
        }
    }

    @Test("a move of a local compiles to the code that a read of it does, in debug and in release",
          arguments: [true, false])
    func moveIsRead(debug: Bool) throws {
        /// A program that stores 42 in one local, then `taken` in another, and prints that one.
        func handingOn(_ taken: Operand) -> IRProgram {
            function(locals: [.int, .int], [
                BasicBlock(statements: [
                    statement(storingIn: 0, .use(.constant(.int(42)))),
                    statement(storingIn: 1, .use(taken)),
                    Statement(destination: nil, value: .call(.printInt, arguments: [read(1)]), range: nowhere),
                ], terminator: .return(nil)),
            ])
        }
        #expect(try compile(handingOn(move(0)), debug: debug) ==
            compile(handingOn(read(0)), debug: debug))
    }

    @Test("a debug build checks integer arithmetic for overflow, and a release build emits no check")
    func overflowChecks() throws {
        let overflows = printing(.binary(.add, .constant(.int(.max)), .constant(.int(1))))
        let report = Array("panic: integer overflow".utf8)
        #expect(try compile(overflows, debug: true).firstRange(of: report) != nil)
        #expect(try compile(overflows, debug: false).firstRange(of: report) == nil)
    }
}
