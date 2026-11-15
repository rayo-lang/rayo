@testable import LLVM
import Testing

struct TargetMachineTests {
    @Test func `a module configured by the host's machine compiles for the host, laid out little-endian`() throws {
        let machine = try TargetMachine(optimizes: false)
        let bench = Workbench()
        machine.configure(bench.module)

        // Every host rayoc builds on is little-endian, which a data layout says with its leading `e`.
        #expect(bench.module.target == machine.triple)
        #expect(bench.module.dataLayout.hasPrefix("e-"))
        #if arch(arm64)
        #expect(machine.triple.hasPrefix("arm64") || machine.triple.hasPrefix("aarch64"))
        #elseif arch(x86_64)
        #expect(machine.triple.hasPrefix("x86_64"))
        #endif
    }

    @Test func `the host's machine compiles for Windows only on Windows`() throws {
        let compilesForWindows = try TargetMachine(optimizes: false).compilesForWindows
        #if os(Windows)
        #expect(compilesForWindows)
        #else
        #expect(!compilesForWindows)
        #endif
    }

    @Test(arguments: [false, true])
    func `the object code of a module names the functions it defines`(optimizes: Bool) throws {
        let machine = try TargetMachine(optimizes: optimizes)
        let bench = Workbench()
        machine.configure(bench.module)
        _ = bench.function(named: "rayo_answer", returning: bench.int64)
        bench.builder.return(bench.int64.constant(42))

        // The module holds no text but its function's name, so the name in the object code is the function's symbol.
        let objectCode = try machine.objectCode(of: bench.module)
        #expect(objectCode.firstRange(of: Array("rayo_answer".utf8)) != nil)
    }

    @Test func `optimising a module inlines a function into its one caller, and drops it`() throws {
        let machine = try TargetMachine(optimizes: true)
        let bench = Workbench()
        machine.configure(bench.module)
        let helper = bench.function(named: "helper", returning: bench.int64)
        bench.builder.return(bench.int64.constant(42))
        helper.setLinkage(.internal)
        _ = bench.function(named: "answer", returning: bench.int64)
        let called = bench.builder.call(helper, [])
        bench.builder.return(try #require(called))

        try machine.optimize(bench.module)
        #expect(bench.module.functions.map(\.name) == ["answer"])
        #expect(bench.module.text.contains("ret i64 42"))
    }

    #if arch(arm64)
    @Test func `a frame of 256 MiB or more for Windows on arm64 fails, where LLVM would end the process`() throws {
        // A frame of 254 MiB compiles. One of 256 MiB fails before LLVM sees it, which would otherwise stop the
        // process, since Windows on arm64 can't unwind it.
        let machine = try TargetMachine(optimizes: false, triple: "aarch64-pc-windows-msvc")
        #expect(try !objectCode(ofFrameOf: 254 << 20, on: machine).isEmpty)
        #expect(throws: LLVMError(message: """
            LLVM can't make a frame of 256 MiB or more for Windows on arm64, and 'framed' keeps 268435456 bytes on \
            its stack
            """)) {
            try objectCode(ofFrameOf: 256 << 20, on: machine)
        }
    }

    /// The object code `machine` writes for a function whose frame holds one stack slot of `bytes` bytes.
    private func objectCode(ofFrameOf bytes: Int, on machine: borrowing TargetMachine) throws -> [UInt8] {
        let bench = Workbench()
        let text = """
            define void @framed() {
              %bytes = alloca [\(bytes) x i8]
              store volatile i8 1, ptr %bytes
              ret void
            }
            """
        let module = try bench.context.parseModule(Array(text.utf8), named: "framed.ll")
        machine.configure(module)
        return try machine.objectCode(of: module)
    }
    #endif
}
