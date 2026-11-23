import LLVM
import Testing
@testable import RayoLLVM
import RayoCheckedProgram
import RayoRuntime
#if os(Windows)
import RayoLLVMTestSupport
import WinSDK
#endif

struct RuntimeTests {
    @Test
    func `a program that panics defines the runtime's panic once and leaves no runtime symbol undefined`() throws {
        let dividesByZero = try compile(printing("divide checked 1, 0"), for: .debug)
        #expect(try symbols(["--undefined-only"], in: dividesByZero).filter { $0.contains("rayo.") } == [])
        // The exit code, a private constant, has no symbol of its own in an ELF object, so only the function is
        // counted.
        let panic = RuntimeFunction.panic.symbol
        #expect(try symbols(["--defined-only"], in: dividesByZero).count(where: { $0.hasSuffix(panic) }) == 1)
    }

    @Test(arguments: Build.allCases)
    func `an object exports only the C entry point, in debug and in release`(build: Build) throws {
        let objectCode = try compile(printing("operand 42"), for: build)
        #expect(try symbols(["--extern-only", "--defined-only"], in: objectCode).map(\.cSymbol) == ["main"])
    }

    @Test func `a program's own functions are defined in its object, and none is exported`() throws {
        // `main` prints what `answer()` returns, so the object needs `answer()`.
        let program = try executable("""
            main "main()"
            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = call "answer()"() @1:1-1:2
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            }
            func "answer()"() -> Int {
            bb0:
              return 42
            }
            """)

        // The object defines `answer()`, and exports only the C entry point.
        let objectCode = try compile(program, for: .debug)
        #expect(try symbols(["--defined-only"], in: objectCode).contains { $0.hasSuffix("answer()") })
        #expect(try symbols(["--extern-only", "--defined-only"], in: objectCode).map(\.cSymbol) == ["main"])
    }

    @Test func `a module declares each runtime function its code calls once, and none that it doesn't call`() throws {
        let printsTwice = try executable("""
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: &Int)"(1) @1:1-1:2
              _ = call builtin "print(_: &Int)"(2) @1:1-1:2
              return
            }
            """)

        try withEmitted(printsTwice) { module in
            #expect(calledRuntimeFunctions(in: module) == [RuntimeFunction.print(.int).symbol])
        }
    }

    @Test func `a module declares the runtime's panic once, however many operators can panic`() throws {
        let dividesTwice = try executable("""
            main "main()"
            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = divide checked 1, 0 @1:1-1:2
              %0 @1:1-1:2 = divide checked 2, 0 @1:1-1:2
              return
            }
            """)

        try withEmitted(dividesTwice) { module in
            #expect(calledRuntimeFunctions(in: module) == [RuntimeFunction.panic.symbol])
        }
    }

    @Test func `every runtime function is one the linked runtime has, of the type a program declares it with`() throws {
        let programModule = try ProgramModule(for: .debug)
        let declared = declaredTypes(in: programModule.emitter.context)

        // The runtime that rayoc links defines each function the program calls, and declares the program's `main`.
        let linked = try programModule.linkedModule()
        let resolved = Dictionary(uniqueKeysWithValues: RuntimeFunction.allCases.map {
            ($0.symbol, linked.function(named: $0.symbol)?.type.anyType.text ?? "none")
        })
        #expect(resolved == declared)
    }

    @Test func `a release build drops the runtime code a program doesn't call, and a debug build keeps it`() throws {
        let empty = try executable(emptyMain)

        // A program that calls nothing in the runtime keeps the runtime's panic in debug, and none of it in release.
        let panic = RuntimeFunction.panic.symbol
        #expect(try symbols([], in: compile(empty, for: .debug)).contains { $0.hasSuffix(panic) })
        #expect(try symbols([], in: compile(empty, for: .release)).filter { $0.contains("rayo.") } == [])
    }

    #if os(Windows)
    @Test func `the host's start keeps a stack guarantee of 64 KiB for the thread it readies`() throws {
        // The JIT runs the Windows host, whose `_setmode` is a stand-in that leaves this process's output as it is.
        let host = try #require(ProgramRuntime.files.first { $0.name == "host-windows.ll" })
        let jit = try JIT()
        try jit.define("_setmode", at: unsafeBitCast(leavingMode, to: UnsafeRawPointer.self))
        try jit.define("SetThreadStackGuarantee", at: unsafeBitCast(settingGuarantee, to: UnsafeRawPointer.self))
        try jit.add(Context().parseModule(host.llvmIR, named: host.name))

        let start = unsafeBitCast(try jit.address(of: "rayo.host.start"), to: (@convention(c) () -> Void).self)
        #expect(rayo_stack_guarantee_after(start) == 64 * 1024)
    }
    #endif
}

#if os(Windows)
/// Stands in for the C runtime's `_setmode`, and changes no stream's mode.
private let leavingMode: @convention(c) (Int32, Int32) -> Int32 = { _, _ in 0 }

/// Calls Windows' `SetThreadStackGuarantee`, and returns its result as the C `BOOL` the host reads.
private let settingGuarantee: @convention(c) (UnsafeMutablePointer<ULONG>?) -> Int32 = {
    SetThreadStackGuarantee($0) ? 1 : 0
}
#endif

/// The symbols of the runtime functions that `module` declares for its code to call: every one but the program's
/// `main`.
private func calledRuntimeFunctions(in module: borrowing Module) -> [String] {
    module.functions.map(\.name).filter { $0.hasPrefix("rayo.") && $0 != RuntimeFunction.main.symbol }
}

/// The type a program declares each runtime function with, in `context`, as LLVM IR writes it, by the function's
/// symbol.
private func declaredTypes(in context: borrowing Context) -> [String: String] {
    let lowering = SignatureLowering(types: LLVMTypes(TypeTable(structs: []), in: context))
    let functions = RuntimeDeclarations(lowering: lowering, in: context)
    return Dictionary(uniqueKeysWithValues: RuntimeFunction.allCases.map {
        ($0.symbol, functions.type(of: $0).anyType.text)
    })
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
