import LLVM
import Testing

struct AttributeTests {
    @Test func `a function's parameters carry the attributes it is declared with, each as LLVM IR writes it`() throws {
        let bench = Workbench()
        let big = bench.context.typeMaker.makeStructType(named: "Big")
        big.setFields([bench.int64, bench.int64, bench.int64], packed: true)
        let pointer = bench.context.pointerType
        let type = bench.context.functionType(
            returning: bench.context.voidType, taking: [pointer, pointer, bench.int64],
        )
        let function = bench.module.addFunction(named: "f", type: type, parameterAttributes: [
            [.structReturn(big.anyType), .noAlias, .writable, .deadOnUnwind, .align(8)],
            [.noAlias, .readOnly, .capturesNone, .noUndef, .nonNull, .dereferenceable(24), .align(8)],
        ])
        bench.builder.position(atEndOf: bench.context.appendBlock(named: "entry", to: function))
        bench.builder.returnVoid()

        // The last parameter, which is given no attributes, carries none.
        try bench.module.verify()
        let declared = "define void @f(ptr dead_on_unwind noalias writable sret(%Big) align 8 %0, "
            + "ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(24) %1, i64 %2)"
        #expect(function.text.contains(declared))
    }

    @Test func `a call's arguments carry the attributes it is built with`() throws {
        let bench = Workbench()
        let pointer = bench.context.pointerType
        let callee = bench.module.addFunction(
            named: "callee", type: bench.context.functionType(returning: bench.context.voidType, taking: [pointer]),
        )
        let caller = bench.function(named: "caller", returning: bench.context.voidType)
        let slot = bench.builder.allocate(bench.int64, alignment: 8)
        bench.builder.call(callee, [slot], parameterAttributes: [[.nonNull, .align(8)]])
        bench.builder.returnVoid()

        try bench.module.verify()
        #expect(caller.text.contains("call void @callee(ptr nonnull align 8 %0)"))
    }
}
