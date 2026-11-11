import LLVM
import Testing

/// A builder's operation on two integers of one width, named as LLVM IR writes its instruction.
enum Operation: String, CaseIterable, Sendable {
    case add, sub, mul, sdiv, srem, and, xor

    func build(with builder: borrowing Builder, _ left: IntValue<I64>, _ right: IntValue<I64>) -> IntValue<I64> {
        switch self {
        case .add: builder.add(left, right)
        case .sub: builder.subtract(left, right)
        case .mul: builder.multiply(left, right)
        case .sdiv: builder.signedDivide(left, right)
        case .srem: builder.signedRemainder(left, right)
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
        (.signedGreater, "sgt"), (.signedGreaterEqual, "sge"),
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
}
