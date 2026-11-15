import LLVM
import Testing
@testable import RayoLLVM

struct FunctionAttributeTests {
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
}
