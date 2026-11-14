import Foundation
import Testing
import LLVM
import RayoIR
import RayoLLVM

struct ObjectCodeTests {
    @Test(arguments: Build.allCases)
    func `a program compiles to an object file for the host, in debug and in release`(build: Build) throws {
        let objectCode = try compile(printing("use 42"), for: build)
        let headers = try llvmTool("llvm-readobj", ["--file-headers"], on: objectCode)
        #expect(headers.contains("Format: \(hostFormat)"))
        #expect(headers.contains("Arch: \(hostArchitecture)\n"))
    }

    @Test(arguments: Build.allCases)
    func `a move of a local compiles to the code that a read of it does, in debug and in release`(
        build: Build,
    ) throws {
        /// A program that stores 42 in one local, then takes it into another with `taking`, and prints that one.
        func handingOn(_ taking: String) throws -> IRExecutable {
            try executable("""
                main "main()"
                func "main()"() -> Void {
                  temp %0: Int
                  temp %1: Int
                bb0:
                  %0 @1:1-1:2 = use 42 @1:1-1:2
                  %1 @1:1-1:2 = use \(taking) %0 @1:1-1:2 @1:1-1:2
                  _ = call builtin "print(_: Int)"(read %1 @1:1-1:2) @1:1-1:2
                  return
                }
                """)
        }

        #expect(try compile(handingOn("move"), for: build) == compile(handingOn("read"), for: build))
    }

    @Test(arguments: Build.allCases)
    func `a declaration compiles to no code, in debug and in release`(build: Build) throws {
        /// The program of one local, whose block holds `statements`.
        func holdingOneLocal(_ statements: String) throws -> IRExecutable {
            try executable("""
                main "main()"
                func "main()"() -> Void {
                  temp %0: Int
                bb0:
                  \(statements)
                  return
                }
                """)
        }

        // The same program of one local, with the local declared and without.
        #expect(try compile(holdingOneLocal("declare %0"), for: build) == compile(holdingOneLocal(""), for: build))
    }

    @Test func `a debug build checks integer arithmetic for overflow, and a release build emits no check`() throws {
        let overflows = try printing("add checked 9223372036854775807, 1")
        let report = Array("panic: integer overflow".utf8)
        #expect(try compile(overflows, for: .debug).firstRange(of: report) != nil)
        #expect(try compile(overflows, for: .release).firstRange(of: report) == nil)
    }
}
