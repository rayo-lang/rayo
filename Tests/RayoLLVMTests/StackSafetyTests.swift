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
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
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
        let undefined = try llvmTool("llvm-nm", ["--undefined-only", "--format=just-symbols"], on: objectCode)
        #expect(undefined.split(separator: "\n").contains("__chkstk"))
        #else
        let disassembly = try llvmTool("llvm-objdump", ["--disassemble"], on: objectCode)
        #expect(disassembly.contains(pageProbe))
        #endif
    }
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
