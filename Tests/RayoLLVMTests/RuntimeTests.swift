import Testing
import RayoIR
import RayoLLVM
import RayoSema

struct RuntimeTests {
    @Test("a program that panics defines the runtime's panic once and leaves no runtime symbol undefined")
    func panicLinked() throws {
        let dividesByZero = try compile(printing(.binary(.divide, .constant(.int(1)), .constant(.int(0)))), for: .debug)
        #expect(try symbols(["--undefined-only"], in: dividesByZero).filter { $0.contains("rayo.") } == [])
        // The exit code, a private constant, has no symbol of its own in an ELF object, so only the function is
        // counted.
        #expect(try symbols(["--defined-only"], in: dividesByZero).count(where: { $0.hasSuffix("rayo.panic") }) == 1)
    }

    @Test(arguments: Build.allCases)
    func `an object exports only the C entry point, in debug and in release`(build: Build) throws {
        let objectCode = try compile(printing(.use(.constant(.int(42)))), for: build)
        #expect(try symbols(["--extern-only", "--defined-only"], in: objectCode).map(\.cSymbol) == ["main"])
    }

    @Test func `a program's own functions are defined in its object, and none is exported`() throws {
        let answer = IRFunction(name: "answer()", parameterCount: 0, result: .int, locals: [], blocks: [
            BasicBlock(statements: [], terminator: .return(.constant(.int(42)))),
        ])
        let main = IRFunction(name: "main()", parameterCount: 0, result: .void, locals: [.temporary(.int)], blocks: [
            BasicBlock(statements: [
                statement(storingIn: 0, .call(.function(FunctionID(index: 1)), arguments: [])),
                statement(printing: read(0)),
            ], terminator: .return(nil)),
        ])
        let objectCode = try compile(IRProgram(functions: [main, answer], main: FunctionID(index: 0)), for: .debug)
        #expect(try symbols(["--defined-only"], in: objectCode).contains { $0.hasSuffix("answer()") })
        #expect(try symbols(["--extern-only", "--defined-only"], in: objectCode).map(\.cSymbol) == ["main"])
    }

    @Test func `a release build drops the runtime code a program doesn't call, and a debug build keeps it`() throws {
        let empty = function(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
        #expect(try symbols([], in: compile(empty, for: .debug)).contains { $0.hasSuffix("rayo.panic") })
        #expect(try symbols([], in: compile(empty, for: .release)).filter { $0.contains("rayo.") } == [])
    }
}

/// The names of the symbols `llvm-nm` lists in `objectCode`, given `options`.
private func symbols(_ options: [String], in objectCode: [UInt8]) throws -> [String] {
    try llvmTool("llvm-nm", options + ["--format=just-symbols"], on: objectCode).split(separator: "\n").map(String.init)
}

private extension String {
    /// The name a C program gives this symbol, without the underscore Mach-O puts before every C name.
    var cSymbol: String {
        #if os(macOS)
        hasPrefix("_") ? String(dropFirst()) : self
        #else
        self
        #endif
    }
}
