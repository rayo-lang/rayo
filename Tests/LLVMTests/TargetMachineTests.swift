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
    @Test func `only a machine for Windows on arm64 limits a function's fixed frame, to under 256 MiB`() throws {
        #expect(try TargetMachine(optimizes: false, triple: "aarch64-pc-windows-msvc").largestFrame == (1 << 28) - 1)
        #expect(try TargetMachine(optimizes: false, triple: "aarch64-unknown-linux-gnu").largestFrame == nil)
        #expect(try TargetMachine(optimizes: false, triple: "arm64-apple-macosx").largestFrame == nil)
    }

    @Test(arguments: [false, true])
    func `a slot of 6 GiB outside the fixed frame compiles for Windows on arm64, optimised or not`(
        optimizes: Bool,
    ) throws {
        // In the fixed frame, a slot of 256 MiB or more would end the process inside LLVM.
        let machine = try TargetMachine(optimizes: optimizes, triple: "aarch64-pc-windows-msvc")
        let bench = Workbench()
        machine.configure(bench.module)
        _ = bench.function(named: "framed", returning: bench.context.voidType)
        let bytes = bench.context.typeMaker.arrayType(of: bench.int64, count: 3 << 28)
        let slot = bench.builder.allocateOutsideFrame(bytes, alignment: 8)
        bench.builder.store(bench.int64.constant(1), to: slot, alignment: 8)
        bench.builder.returnVoid()

        // Optimising leaves the slot outside the frame, since its count is read through a volatile load.
        if optimizes { try machine.optimize(bench.module) }
        #expect(try !machine.objectCode(of: bench.module).isEmpty)
    }
    #endif
}
