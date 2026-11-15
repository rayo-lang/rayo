import LLVM
import Testing

/// A builder's operation on two integers of one width, named as LLVM IR writes its instruction.
enum Operation: String, CaseIterable, Sendable {
    case add, sub, mul, sdiv, srem, udiv, urem, and, xor

    func build(with builder: borrowing Builder, _ left: IntValue<I64>, _ right: IntValue<I64>) -> IntValue<I64> {
        switch self {
        case .add: builder.add(left, right)
        case .sub: builder.subtract(left, right)
        case .mul: builder.multiply(left, right)
        case .sdiv: builder.signedDivide(left, right)
        case .srem: builder.signedRemainder(left, right)
        case .udiv: builder.unsignedDivide(left, right)
        case .urem: builder.unsignedRemainder(left, right)
        case .and: builder.and(left, right)
        case .xor: builder.xor(left, right)
        }
    }
}

struct ArithmeticTests {
    @Test(arguments: Operation.allCases)
    func `an operation on two integers of one width builds LLVM's instruction for it`(operation: Operation) throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64, bench.int64])
        let left = parameter(0, of: function, as: I64.self)
        let right = parameter(1, of: function, as: I64.self)
        bench.builder.return(operation.build(with: bench.builder, left, right))

        try bench.module.verify()
        #expect(function.text == """
            define i64 @f(i64 %0, i64 %1) {
            entry:
              %2 = \(operation.rawValue) i64 %0, %1
              ret i64 %2
            }

            """)
    }

    @Test(arguments: [
        (IntegerPredicate.equal, "eq"), (.notEqual, "ne"), (.signedLess, "slt"), (.signedLessEqual, "sle"),
        (.signedGreater, "sgt"), (.signedGreaterEqual, "sge"), (.unsignedLess, "ult"), (.unsignedLessEqual, "ule"),
        (.unsignedGreater, "ugt"), (.unsignedGreaterEqual, "uge"),
    ])
    func `a comparison of two integers builds LLVM's icmp, which gives an i1`(
        predicate: IntegerPredicate, written: String,
    ) throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.bool, taking: [bench.int64, bench.int64])
        let left = parameter(0, of: function, as: I64.self)
        let right = parameter(1, of: function, as: I64.self)
        bench.builder.return(bench.builder.compare(predicate, left, right))

        try bench.module.verify()
        #expect(function.text.contains("%2 = icmp \(written) i64 %0, %1\n"))
    }

    @Test func `a select picks between two integers on an i1`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64,
                                      taking: [bench.bool, bench.int64, bench.int64])
        let condition = parameter(0, of: function, as: I1.self)
        let then = parameter(1, of: function, as: I64.self)
        let otherwise = parameter(2, of: function, as: I64.self)
        bench.builder.return(bench.builder.select(condition, then, otherwise))

        try bench.module.verify()
        #expect(function.text.contains("%3 = select i1 %0, i64 %1, i64 %2\n"))
    }

    @Test func `a constant holds the low bits of its value, sign-extended in LLVM IR`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64)
        let minusOne = bench.int64.constant(-1)
        bench.builder.return(bench.builder.add(minusOne, bench.int64.constant(.max)))

        try bench.module.verify()
        #expect(minusOne.anyValue.text == "i64 -1")
        #expect(bench.bool.constant(1).anyValue.text == "i1 true")
        #expect(function.text.contains("ret i64 9223372036854775806"))
    }

    @Test func `an integer constant gives its value, sign-extended, and a value that is no constant none`() {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64])

        #expect(bench.int64.constant(-5).constantValue == -5)
        #expect(bench.bool.constant(1).constantValue == -1)
        #expect(parameter(0, of: function, as: I64.self).constantValue == nil)
    }

    @Test func `an integer truncates to a narrower width, and zero-extends to a wider one`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64])
        let low = bench.builder.truncate(parameter(0, of: function, as: I64.self), to: bench.bool)
        bench.builder.return(bench.builder.zeroExtend(low, to: bench.int64))

        try bench.module.verify()
        #expect(function.text.contains("""
              %1 = trunc i64 %0 to i1
              %2 = zext i1 %1 to i64
              ret i64 %2
            """))
    }

    @Test func `an integer whose width the program decides builds the instructions one of a fixed width does`() throws {
        let bench = Workbench()
        let int32 = bench.context.typeMaker.integerType(bitWidth: 32)
        let function = bench.function(named: "f", returning: bench.bool, taking: [int32, int32])
        let left = try #require(AnyIntValue(function.parameter(at: 0)))
        let right = try #require(AnyIntValue(function.parameter(at: 1)))
        let sum = bench.builder.add(left, int32.constant(-1))
        let product = bench.builder.multiply(sum, right)
        bench.builder.return(bench.builder.compare(.signedLess, product, right))

        try bench.module.verify()
        #expect(function.text.contains("""
              %2 = add i32 %0, -1
              %3 = mul i32 %2, %1
              %4 = icmp slt i32 %3, %1
            """))
    }

    @Test func `a constant of an integer whose width the program decides holds the low bits of its value`() {
        let bench = Workbench()
        let int128 = bench.context.typeMaker.integerType(bitWidth: 128)
        let int8 = bench.context.typeMaker.integerType(bitWidth: 8)

        #expect(int128.constant(Int128(1) << 100).anyValue.text == "i128 1267650600228229401496703205376")
        #expect(int128.constant(-1).anyValue.text == "i128 -1")
        #expect(int8.constant(200).anyValue.text == "i8 -56")
    }

    @Test func `an integer whose width the program decides truncates, and extends with zeros or its sign`() throws {
        let bench = Workbench()
        let int16 = bench.context.typeMaker.integerType(bitWidth: 16)
        let int64 = bench.context.typeMaker.integerType(bitWidth: 64)
        let function = bench.function(named: "f", returning: int64, taking: [int64])
        let low = bench.builder.truncate(try #require(AnyIntValue(function.parameter(at: 0))), to: int16)
        let signed = bench.builder.signExtend(low, to: int64)
        bench.builder.return(bench.builder.or(signed, bench.builder.zeroExtend(low, to: int64)))

        try bench.module.verify()
        #expect(function.text.contains("""
              %1 = trunc i64 %0 to i16
              %2 = sext i16 %1 to i64
              %3 = zext i16 %1 to i64
              %4 = or i64 %2, %3
            """))
    }
}
