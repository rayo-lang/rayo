import LLVM
import Testing

struct TypeTests {
    @Test func `an integer value converts to an integer of its own width, and of no other`() {
        let bench = Workbench()
        let int64 = bench.int64.constant(7).anyValue

        #expect(IntValue<I64>(int64) != nil)
        #expect(IntValue<I1>(int64) == nil)
        #expect(IntValue<I32>(int64) == nil)
    }

    @Test func `a value that is no integer converts to no integer`() {
        let bench = Workbench()
        let bytes = bench.context.constant(bytes: Array("hi".utf8))

        #expect(IntValue<I8>(bytes) == nil)
    }

    @Test func `a struct or an array converts to an aggregate, and an integer doesn't`() {
        let bench = Workbench()
        let pair = bench.context.makeStructType(named: "Pair")
        pair.setFields([bench.int64, bench.bool], packed: false)
        let function = bench.function(named: "f", returning: bench.context.voidType, taking: [pair])

        #expect(AggregateValue(function.parameter(at: 0)) != nil)
        #expect(AggregateValue(bench.context.constant(bytes: Array("hi".utf8))) != nil)
        #expect(AggregateValue(bench.int64.constant(1)) == nil)
    }

    @Test func `a type says what LLVM IR writes it as`() {
        let bench = Workbench()
        let pair = bench.context.makeStructType(named: "Pair")
        pair.setFields([bench.int64, bench.bool], packed: true)

        #expect(bench.int64.anyType.text == "i64")
        #expect(bench.context.voidType.isVoid)
        #expect(bench.context.arrayType(of: bench.context.integerType(I8.self), count: 3).text == "[3 x i8]")
        #expect(pair.anyType.text == "%Pair = type <{ i64, i1 }>")
        #expect(bench.context.functionType(returning: pair, taking: [bench.int64]).parameters == [bench.int64.anyType])
        #expect(bench.context.functionType(returning: pair, taking: [bench.int64]).result == pair.anyType)
    }

    @Test func `a struct's fields are laid out packed or padded, as it is given them`() throws {
        let bench = Workbench()
        let packed = bench.context.makeStructType(named: "Packed")
        packed.setFields([bench.int64, bench.bool], packed: true)
        let padded = bench.context.makeStructType(named: "Padded")
        padded.setFields([bench.int64, bench.bool], packed: false)
        _ = bench.function(named: "f", returning: bench.context.voidType, taking: [packed, padded])
        bench.builder.returnVoid()

        try bench.module.verify()
        #expect(bench.module.text.contains("%Packed = type <{ i64, i1 }>\n%Padded = type { i64, i1 }\n"))
    }

    @Test func `a literal struct has no name, and is written by its fields`() throws {
        let bench = Workbench()
        let pair = bench.context.structType(of: [bench.bool, bench.int64])
        let function = bench.function(named: "f", returning: pair, taking: [bench.bool, bench.int64])
        let withFlag = bench.builder.insertValue(function.parameter(at: 0), into: pair.poison, at: 0)
        bench.builder.return(bench.builder.insertValue(function.parameter(at: 1), into: withFlag, at: 1))

        try bench.module.verify()
        #expect(pair.anyType.text == "{ i1, i64 }")
    }

    @Test func `a pointer's type is LLVM's one opaque pointer type`() {
        #expect(Workbench().context.pointerType.text == "ptr")
    }
}
