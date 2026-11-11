import LLVM
import Testing

struct CallTests {
    @Test func `a call gives the function's result, or none where the function returns nothing`() throws {
        let bench = Workbench()
        let void = bench.function(named: "nothing", returning: bench.context.voidType)
        bench.builder.returnVoid()
        let one = bench.function(named: "one", returning: bench.int64)
        bench.builder.return(bench.int64.constant(1))
        let caller = bench.function(named: "caller", returning: bench.int64)

        // The expectations take the calls' results, since they can't take a builder, which isn't copyable.
        let nothing = bench.builder.call(void, [])
        let called = bench.builder.call(one, [])
        #expect(nothing == nil)
        bench.builder.return(try #require(called))

        try bench.module.verify()
        #expect(caller.text.contains("  call void @nothing()\n  %0 = call i64 @one()\n  ret i64 %0\n"))
    }

    @Test func `an intrinsic that reports overflow gives the result and the overflow as its two fields`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.bool, taking: [bench.int64, bench.int64])
        let add = bench.module.intrinsic(named: "llvm.sadd.with.overflow", overloadedOn: bench.int64)
        // The expectations take the builder's results, since they can't take a builder, which isn't copyable.
        let call = bench.builder.call(add, [function.parameter(at: 0), function.parameter(at: 1)])
        let pair = try #require(call)
        let field = bench.builder.extractValue(from: pair, at: 1)
        bench.builder.return(try #require(IntValue<I1>(field)))

        try bench.module.verify()
        #expect(function.text.contains("""
              %2 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %0, i64 %1)
              %3 = extractvalue { i64, i1 } %2, 1
              ret i1 %3
            """))
    }
}
