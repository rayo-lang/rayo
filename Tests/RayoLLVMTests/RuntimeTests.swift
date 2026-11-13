import Testing
import RayoIR
import RayoLLVM
import RayoSema

struct RuntimeTests {
    @Test
    func `a program that panics defines the runtime's panic once and leaves no runtime symbol undefined`() throws {
        let division = Rvalue.binary(.divide(.checked), .constant(.int(1)), .constant(.int(0)))
        let dividesByZero = try compile(printing(division), for: .debug)
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
        // `main` prints what `answer()` returns, so the object needs `answer()`.
        let answer = handWritten(name: "answer()", parameterCount: 0, result: .int, locals: [], blocks: [
            BasicBlock(statements: [], terminator: .return(.constant(.int(42)))),
        ])
        let main = mainFunction(locals: [.int], [
            BasicBlock(statements: [
                statement(storingIn: 0, .call(.function(FunctionID(index: 1)), arguments: [])),
                statement(printing: read(0)),
            ], terminator: .return(nil)),
        ])

        // The object defines `answer()`, and exports only the C entry point.
        let objectCode = try compile(program(of: [main, answer]), for: .debug)
        #expect(try symbols(["--defined-only"], in: objectCode).contains { $0.hasSuffix("answer()") })
        #expect(try symbols(["--extern-only", "--defined-only"], in: objectCode).map(\.cSymbol) == ["main"])
    }

    @Test func `a module declares each runtime function its code calls once, and none that it doesn't call`() throws {
        let printsTwice = program(locals: [], [
            BasicBlock(statements: [
                statement(printing: .constant(.int(1))),
                statement(printing: .constant(.int(2))),
            ], terminator: .return(nil)),
        ])

        try withEmitted(printsTwice) { module in
            let runtimeFunctions = module.functions.map(\.name).filter { $0.hasPrefix("rayo.") && $0 != "rayo.main" }
            #expect(runtimeFunctions == ["rayo.print_int"])
        }
    }

    @Test func `a module declares the runtime's panic once, however many operators can panic`() throws {
        let dividesTwice = program(locals: [.int], [
            BasicBlock(statements: [
                statement(storingIn: 0, .binary(.divide(.checked), .constant(.int(1)), .constant(.int(0)))),
                statement(storingIn: 0, .binary(.divide(.checked), .constant(.int(2)), .constant(.int(0)))),
            ], terminator: .return(nil)),
        ])

        try withEmitted(dividesTwice) { module in
            let runtimeFunctions = module.functions.map(\.name).filter { $0.hasPrefix("rayo.") && $0 != "rayo.main" }
            #expect(runtimeFunctions == ["rayo.panic"])
        }
    }

    @Test func `a release build drops the runtime code a program doesn't call, and a debug build keeps it`() throws {
        let empty = program(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])

        // A program that calls nothing in the runtime keeps the runtime's panic in debug, and none of it in release.
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
