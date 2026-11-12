import LLVM
import Testing

struct StructTests {
    @Test func `a struct's value is made from poison, one field inserted at a time`() throws {
        let bench = Workbench()
        let pair = bench.context.makeStructType(named: "Pair")
        pair.setFields([bench.int64, bench.bool], packed: true)
        let function = bench.function(named: "f", returning: pair, taking: [bench.int64, bench.bool])

        // Insert the Bool before the Int, so each lands at the index it is given, whatever the order.
        let withFlag = bench.builder.insertValue(function.parameter(at: 1), into: pair.poison, at: 1)
        bench.builder.return(bench.builder.insertValue(function.parameter(at: 0), into: withFlag, at: 0))

        try bench.module.verify()
        #expect(pair.poison.anyValue.isUndefined)
        #expect(function.text.contains("""
              %2 = insertvalue %Pair poison, i1 %1, 1
              %3 = insertvalue %Pair %2, i64 %0, 0
              ret %Pair %3
            """))
    }

    @Test func `a field's pointer points into the struct that a pointer points to`() throws {
        let bench = Workbench()
        let pair = bench.context.makeStructType(named: "Pair")
        pair.setFields([bench.int64, bench.bool], packed: true)
        let function = bench.function(named: "f", returning: bench.bool, taking: [pair])
        let slot = bench.builder.allocate(pair, alignment: 8)
        bench.builder.store(function.parameter(at: 0), to: slot, alignment: 8)
        let flag = bench.builder.fieldPointer(to: 1, of: pair, at: slot)
        bench.builder.return(bench.builder.load(bench.bool, from: flag, alignment: 1))

        try bench.module.verify()
        #expect(function.text.contains("""
              %2 = getelementptr inbounds nuw %Pair, ptr %1, i32 0, i32 1
              %3 = load i1, ptr %2, align 1
            """))
    }
}
