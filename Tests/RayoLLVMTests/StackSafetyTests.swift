import LLVM
import Testing
@testable import RayoLLVM

struct StackSafetyTests {
    @Test(arguments: Build.allCases)
    func `every function the program and the runtime define makes its frame safely on the host`(build: Build) throws {
        // `main` calls `answer()`, so the program defines a function of its own beside the runtime's.
        let program = try executable("""
            main "main()"
            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = call "answer()"() @1:1-1:2
              _ = call builtin "print(_: &Int)"(read %0 @1:1-1:2) @1:1-1:2
              return
            }
            func "answer()"() -> Int {
            bb0:
              return 42
            }
            """)
        let programModule = try ProgramModule(for: build)
        programModule.emit(program)
        let module = try programModule.linkedModule()

        // Windows probes a large frame through `__chkstk` already, and needs an unwind table in every function. Every
        // other host needs the frame probed.
        let defined = module.functions.filter { !$0.isDeclaration }
        #expect(defined.contains { $0.name == "answer()" })
        for function in defined {
            #if os(Windows)
            #expect(function.carries(.unwindTable), "\(function.name)")
            #expect(!function.carries(.inlineStackProbes), "\(function.name)")
            #else
            #expect(function.carries(.inlineStackProbes), "\(function.name)")
            #expect(!function.carries(.unwindTable), "\(function.name)")
            #endif
        }
    }

    @Test(arguments: Build.allCases)
    func `a frame larger than a page is touched a page at a time as it is made, in debug and in release`(
        build: Build,
    ) throws {
        // `main` fills an array of 32 MB and prints its last element, so the array stays in its frame.
        let program = try executable("""
            main "main()"
            func "main()"() -> Void {
              var %0 a: [4000000 of Int] @1:1-1:1
            bb0:
              %0 @1:1-1:2 = fill 4000000 of 1 @1:1-1:2
              \(printInt("%0[3999999]"))
              return
            }
            """)
        let objectCode = try compile(program, for: build)

        #if os(Windows)
        // Windows probes a frame by a call to `__chkstk`, which touches each of its pages in turn, so the object
        // needs that function from the C runtime.
        #expect(try symbols(["--undefined-only"], in: objectCode).contains("__chkstk"))
        #else
        let disassembly = try llvmTool("llvm-objdump", ["--disassemble"], on: objectCode)
        #expect(disassembly.contains(pageProbe))
        #endif
    }

    @Test(arguments: Build.allCases)
    func `a frame of more than 4 GiB, of values that each fit on the stack, compiles in debug and in release`(
        build: Build,
    ) throws {
        // LLVM warns of a frame of more than 4 GiB, which fails nothing: the frame is made, probed, like any other.
        #expect(try !compile(executable(sixGiBOfSlots), for: build).isEmpty)
    }

    #if arch(arm64)
    @Test(arguments: Build.allCases)
    func `on Windows on arm64, the slots a fixed frame has no room for grow the stack as the function begins`(
        build: Build,
    ) throws {
        // Windows on arm64 can't unwind a fixed frame of 256 MiB or more, so each array goes outside it. A slot
        // whose count LLVM can't see is made as the function runs.
        let programModule = try ProgramModule(for: build, triple: "aarch64-pc-windows-msvc")
        programModule.emit(try executable(sixGiBOfSlots))
        try LLVMEmitter.ready(programModule.emitter.module, for: programModule.target,
                              exporting: [RuntimeFunction.main.symbol])

        let main = try function(named: RuntimeFunction.main.symbol, in: programModule.emitter.module).text
        #expect(main.components(separatedBy: "alloca [268435455 x i64], i64 %").count - 1 == 3)
        #expect(try !programModule.target.objectCode(of: programModule.emitter.module).isEmpty)
    }
    #endif

    /// A `main` with three arrays of 2147483640 bytes, each within the bound on one value, which take about 6 GiB.
    private let sixGiBOfSlots = """
        main "main()"
        func "main()"() -> Void {
          var %0 a: [268435455 of Int] @1:1-1:1
          var %1 b: [268435455 of Int] @1:1-1:1
          var %2 c: [268435455 of Int] @1:1-1:1
        bb0:
          %0 @1:1-1:2 = fill 268435455 of 1 @1:1-1:2
          %1 @1:1-1:2 = fill 268435455 of 2 @1:1-1:2
          %2 @1:1-1:2 = fill 268435455 of 3 @1:1-1:2
          \(printInt("%0[268435454]"))
          \(printInt("%1[0]"))
          \(printInt("%2[0]"))
          return
        }
        """
}

#if !os(Windows)
#if arch(arm64)
/// The load that probes one page of a frame, at the stack pointer, on arm64.
private let pageProbe = "ldr\txzr, [sp]"
#elseif arch(x86_64)
/// The store that probes one page of a frame, at the stack pointer, on x86-64.
private let pageProbe = "movq\t$0x0, (%rsp)"
#endif
#endif
