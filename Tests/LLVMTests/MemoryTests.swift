import LLVM
import Testing

struct MemoryTests {
    @Test func `a stack slot holds what is stored to it, each access aligned as it is told`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64])
        let slot = bench.builder.allocate(bench.int64, alignment: 8)
        bench.builder.store(function.parameter(at: 0), to: slot, alignment: 8)
        bench.builder.return(bench.builder.load(bench.int64, from: slot, alignment: 4))

        try bench.module.verify()
        #expect(function.text.contains("""
              %1 = alloca i64, align 8
              store i64 %0, ptr %1, align 8
              %2 = load i64, ptr %1, align 4
              ret i64 %2
            """))
    }

    @Test func `a global's pointer is what code loads its value through`() throws {
        let bench = Workbench()
        let limit = bench.module.addGlobal(named: "limit", initializer: bench.int64.constant(10))
        let function = bench.function(named: "f", returning: bench.int64)
        bench.builder.return(bench.builder.load(bench.int64, from: limit.pointer, alignment: 8))

        try bench.module.verify()
        #expect(function.text.contains("%0 = load i64, ptr @limit, align 8\n"))
    }

    @Test func `memory is copied between two pointers by a call of memcpy, of a constant size`() throws {
        let bench = Workbench()
        let pointer = bench.context.pointerType
        let function = bench.function(named: "f", returning: bench.context.voidType, taking: [pointer, pointer])
        let destination = try #require(PointerValue(function.parameter(at: 0)))
        let source = try #require(PointerValue(function.parameter(at: 1)))
        bench.builder.copyMemory(to: destination, from: source, size: 24, alignment: 8)
        bench.builder.returnVoid()

        try bench.module.verify()
        let copy = "call void @llvm.memcpy.p0.p0.i64(ptr align 8 %0, ptr align 8 %1, i64 24, i1 false)"
        #expect(function.text.contains(copy))
    }

    @Test func `a pointer converts to a pointer value, and an integer doesn't`() {
        let bench = Workbench()
        let function = bench.function(
            named: "f", returning: bench.context.voidType, taking: [bench.context.pointerType, bench.int64],
        )

        #expect(PointerValue(function.parameter(at: 0)) != nil)
        #expect(PointerValue(function.parameter(at: 1)) == nil)
    }

    @Test func `the builder says which block it adds instructions to`() {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.context.voidType)
        let next = bench.context.appendBlock(named: "next", to: function)
        bench.builder.position(atEndOf: next)

        #expect(bench.builder.insertionBlock == next)
    }
}
