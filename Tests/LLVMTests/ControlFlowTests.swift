import LLVM
import Testing

struct ControlFlowTests {
    @Test func `a branch goes on to a block, or to one of two on an i1`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.context.voidType, taking: [bench.bool])
        let then = bench.context.appendBlock(named: "then", to: function)
        let otherwise = bench.context.appendBlock(named: "otherwise", to: function)
        bench.builder.branch(if: parameter(0, of: function, as: I1.self), then: then, else: otherwise)
        bench.builder.position(atEndOf: then)
        bench.builder.branch(to: otherwise)
        bench.builder.position(atEndOf: otherwise)
        bench.builder.unreachable()

        try bench.module.verify()
        #expect(function.text == """
            define void @f(i1 %0) {
            entry:
              br i1 %0, label %then, label %otherwise

            then:                                             ; preds = %entry
              br label %otherwise

            otherwise:                                        ; preds = %then, %entry
              unreachable
            }

            """)
    }
}
