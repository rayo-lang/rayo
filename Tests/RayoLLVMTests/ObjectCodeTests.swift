import Foundation
import Testing
import LLVM
import RayoIR
import RayoLLVM

struct ObjectCodeTests {
    @Test(arguments: Build.allCases)
    func `a program compiles to an object file for the host, in debug and in release`(build: Build) throws {
        let objectCode = try compile(printing("operand 42"), for: build)
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
                  %0 @1:1-1:2 = operand 42 @1:1-1:2
                  %1 @1:1-1:2 = operand \(taking) %0 @1:1-1:2 @1:1-1:2
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

    @Test(.timeLimit(.minutes(1)), arguments: Build.allCases)
    func `a program that fills, passes and returns arrays of a hundred thousand elements compiles quickly`(
        build: Build,
    ) throws {
        // `main` fills an array of Ints and an array of arrays of Trios, and hands each through a function that
        // returns a copy of what it borrows. A third function relays an array of arrays of Pairs, which no code calls.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 ints: [100000 of Int] @1:1-1:1
              var %1 trio: Trio @1:1-1:1
              temp %2: [100 of Trio]
              var %3 trios: [1000 of [100 of Trio]] @1:1-1:1
            bb0:
              %0 @1:1-1:2 = fill 100000 of 0 @1:1-1:2
              %0 @1:1-1:2 = call "relay(_: [100000 of Int])"(read %0 @1:1-1:2) @1:1-1:2
              \(printInt("%0[99999]"))
              %1 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(2, 3, true) @1:1-1:2
              %2 @1:1-1:2 = fill 100 of read %1 @1:1-1:2 @1:1-1:2
              %3 @1:1-1:2 = fill 1000 of read %2 @1:1-1:2 @1:1-1:2
              %3 @1:1-1:2 = call "relay(_: [1000 of [100 of Trio]])"(read %3 @1:1-1:2) @1:1-1:2
              \(printInt("%3[999][99].0"))
              return
            }
            func "relay(_: [100000 of Int])"(_: &[100000 of Int]) -> [100000 of Int] {
              param %0 a: &[100000 of Int] @1:1-1:1
              temp %1: [100000 of Int]
            bb0:
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              return move %1 @1:1-1:2
            }
            func "relay(_: [1000 of [100 of Trio]])"(_: &[1000 of [100 of Trio]]) -> [1000 of [100 of Trio]] {
              param %0 a: &[1000 of [100 of Trio]] @1:1-1:1
              temp %1: [1000 of [100 of Trio]]
            bb0:
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              return move %1 @1:1-1:2
            }
            func "relay(_: [100000 of [2 of Pair]])"(_: &[100000 of [2 of Pair]]) -> [100000 of [2 of Pair]] {
              param %0 a: &[100000 of [2 of Pair]] @1:1-1:1
              temp %1: [100000 of [2 of Pair]]
            bb0:
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              return move %1 @1:1-1:2
            }
            """
        let objectCode = try compile(executable(text), for: build)
        #expect(!objectCode.isEmpty)
    }

    @Test func `a debug build checks integer arithmetic for overflow, and a release build emits no check`() throws {
        let overflows = try printing("add checked 9223372036854775807, 1")
        let report = Array("panic: integer overflow".utf8)
        #expect(try compile(overflows, for: .debug).firstRange(of: report) != nil)
        #expect(try compile(overflows, for: .release).firstRange(of: report) == nil)
    }
}
