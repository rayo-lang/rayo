import LLVM
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
}
