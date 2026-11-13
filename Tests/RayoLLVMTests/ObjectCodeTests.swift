import Foundation
import Testing
import LLVM
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

    @Test(arguments: Build.allCases)
    func `a move of a local compiles to the code that a read of it does, in debug and in release`(
        build: Build,
    ) throws {
        /// A program that stores 42 in one local, then `taken` in another, and prints that one.
        func handingOn(_ taken: Operand) -> IRExecutable {
            program(locals: [.int, .int], [
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
        // The same program of one local, with the local declared and without.
        let declared = program(locals: [.int], [
            BasicBlock(statements: [.declare(LocalID(index: 0))], terminator: .return(nil)),
        ])
        let empty = program(locals: [.int], [BasicBlock(statements: [], terminator: .return(nil))])

        #expect(try compile(declared, for: build) == compile(empty, for: build))
    }

    @Test func `a debug build checks integer arithmetic for overflow, and a release build emits no check`() throws {
        let overflows = printing(.binary(.add(.checked), .constant(.int(.max)), .constant(.int(1))))
        let report = Array("panic: integer overflow".utf8)
        #expect(try compile(overflows, for: .debug).firstRange(of: report) != nil)
        #expect(try compile(overflows, for: .release).firstRange(of: report) == nil)
    }
}
