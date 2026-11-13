import RayoLLVM
import RayoIR
import Testing

/// `OperatorEmitter` emits each operator here as a unit, on the parameters of a function of its own, which the test
/// calls in its own process. A whole program would pass its operators literals from its entry point, which a
/// release build's optimiser folds before the emitted instructions run.
@Suite("Operators on Int and Bool values")
struct OperatorTests {
    @Test(arguments: [
        (.add(.checked), 7, -5, 2), (.subtract(.checked), 7, -5, 12), (.multiply(.checked), 7, -5, -35),
    ] as [(IRBinaryOperator, Int64, Int64, Int64)], Build.allCases)
    func `'+', '-' and '*' compute what they name, in every build`(
        operation: (IRBinaryOperator, Int64, Int64, Int64), build: Build,
    ) throws {
        let (op, left, right, result) = operation
        #expect(try outcome(of: op, left, right, in: build) == .int(result))
    }

    @Test(arguments: [
        (.add(.checked), .max, 1, .min),
        (.subtract(.checked), .min, 1, .max),
        (.multiply(.checked), 1 << 62, 2, .min),
    ] as [(IRBinaryOperator, Int64, Int64, Int64)])
    func `an overflowing '+', '-' or '*' panics where overflow is checked, and wraps where it isn't`(
        op: IRBinaryOperator, left: Int64, right: Int64, wrapped: Int64,
    ) throws {
        #expect(try outcome(of: op, left, right, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: op, left, right, in: .release) == .int(wrapped))
    }

    @Test(arguments: [
        (.add(.wrapping), .max, 1, .min),
        (.subtract(.wrapping), .min, 1, .max),
        (.multiply(.wrapping), 1 << 62, 2, .min),
        (.divide(.wrapping), .min, -1, .min),
    ] as [(IRBinaryOperator, Int64, Int64, Int64)], Build.allCases)
    func `wrapping arithmetic wraps on overflow, in every build`(
        operation: (IRBinaryOperator, Int64, Int64, Int64), build: Build,
    ) throws {
        let (op, left, right, wrapped) = operation
        #expect(try outcome(of: op, left, right, in: build) == .int(wrapped))
    }

    @Test(arguments: Build.allCases)
    func `a wrapping '/' still panics on a zero divisor, in every build`(build: Build) throws {
        #expect(try outcome(of: .divide(.wrapping), 1, 0, in: build) == .panics("division by zero"))
    }

    @Test(arguments: Build.allCases)
    func `wrapping negation wraps Int.min to itself, in every build`(build: Build) throws {
        #expect(try outcome(of: .negate(.wrapping), .min, in: build) == .int(.min))
    }

    @Test(arguments: Build.allCases)
    func `'-' negates an Int, in every build`(build: Build) throws {
        #expect(try outcome(of: .negate(.checked), 5, in: build) == .int(-5))
    }

    @Test func `negating Int.min panics where overflow is checked, and wraps to Int.min where it isn't`() throws {
        #expect(try outcome(of: .negate(.checked), .min, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: .negate(.checked), .min, in: .release) == .int(.min))
    }

    @Test(arguments: [
        (7, 2, 3), (-7, 2, -3), (7, -2, -3), (-7, -2, 3), (5, -1, -5), (.max, -1, -.max),
        (.min, 2, -4_611_686_018_427_387_904),
    ] as [(Int64, Int64, Int64)], Build.allCases)
    func `'/' rounds toward zero, in every build`(operands: (Int64, Int64, Int64), build: Build) throws {
        let (left, right, quotient) = operands
        #expect(try outcome(of: .divide(.checked), left, right, in: build) == .int(quotient))
    }

    @Test func `Int.min / -1 panics where overflow is checked, and wraps to Int.min where it isn't`() throws {
        #expect(try outcome(of: .divide(.checked), .min, -1, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: .divide(.checked), .min, -1, in: .release) == .int(.min))
    }

    @Test(arguments: [
        (7, 3, 1), (-7, 3, -1), (7, -3, 1), (-7, -3, -1), (7, -1, 0), (.min, -1, 0), (.min, 3, -2),
    ] as [(Int64, Int64, Int64)], Build.allCases)
    func `'%' takes the dividend's sign, and a remainder by -1 is 0, Int.min's too, in every build`(
        operands: (Int64, Int64, Int64), build: Build,
    ) throws {
        let (left, right, remainder) = operands
        #expect(try outcome(of: .remainder, left, right, in: build) == .int(remainder))
    }

    @Test(arguments: [
        (.divide(.checked), "division by zero"), (.remainder, "remainder by zero"),
    ] as [(IRBinaryOperator, String)], Build.allCases)
    func `'/' and '%' by zero panic in every build`(operation: (IRBinaryOperator, String), build: Build) throws {
        let (op, reason) = operation
        #expect(try outcome(of: op, 7, 0, in: build) == .panics(reason))
    }

    @Test(arguments: [
        (.equal, [false, true, false]),
        (.notEqual, [true, false, true]),
        (.less, [true, false, false]),
        (.lessEqual, [true, true, false]),
        (.greater, [false, false, true]),
        (.greaterEqual, [false, true, true]),
    ] as [(IRBinaryOperator, [Bool])])
    func `a comparison of two Ints orders them as signed`(op: IRBinaryOperator, againstZero: [Bool]) throws {
        // Each operator compares -1, 0 and 1 against 0, which a comparison of unsigned values would get wrong.
        for (left, expected) in zip([-1, 0, 1] as [Int64], againstZero) {
            #expect(try outcome(of: op, left, 0, in: .debug) == .bool(expected))
        }
    }

    @Test(arguments: [
        (true, true, true), (true, false, false), (false, true, false), (false, false, true),
    ])
    func `'==' and '!=' compare two Bools`(left: Bool, right: Bool, equal: Bool) throws {
        #expect(try outcome(of: .equal, left, right) == .bool(equal))
        #expect(try outcome(of: .notEqual, left, right) == .bool(!equal))
    }

    @Test(arguments: [(true, false), (false, true)])
    func `'!' inverts a Bool`(operand: Bool, inverted: Bool) throws {
        #expect(try outcome(of: .not, operand) == .bool(inverted))
    }
}

/// Operators keep the results Rayo gives them, and their panics, through a release build's optimiser, which may
/// take an operation whose result LLVM leaves undefined never to happen, and would then give each expression
/// another result.
@Suite("Operators optimised as a release build is")
struct OptimizedOperatorTests {
    @Test func `Int.max + 1 wraps below Int.max`() throws {
        let outcome = try releaseOutcome(of: .max) { emit, a in try emit(.less, emit(.add(.checked), a, 1), a) }
        #expect(outcome == .bool(true))
    }

    @Test func `Int.min - 1 wraps above Int.min`() throws {
        let outcome = try releaseOutcome(of: .min) { emit, a in try emit(.greater, emit(.subtract(.checked), a, 1), a) }
        #expect(outcome == .bool(true))
    }

    @Test func `Int.min * 2 wraps to 0`() throws {
        let outcome = try releaseOutcome(of: .min) { emit, a in try emit(.equal, emit(.multiply(.checked), a, 2), 0) }
        #expect(outcome == .bool(true))
    }

    @Test func `negating Int.min wraps to Int.min`() throws {
        let outcome = try releaseOutcome(of: .min) { emit, a in try emit(.equal, emit(.negate(.checked), a), a) }
        #expect(outcome == .bool(true))
    }

    @Test func `Int.min / -1 wraps to Int.min, where the optimiser knows the divisor`() throws {
        let outcome = try releaseOutcome(of: .min) { emit, a in try emit(.equal, emit(.divide(.checked), a, -1), a) }
        #expect(outcome == .bool(true))
    }

    @Test func `7 / 2 rounds to 3, the quotient of a division with a remainder`() throws {
        let outcome = try releaseOutcome(of: 7) { emit, a in try emit(.equal, emit(.divide(.checked), a, 2), 3) }
        #expect(outcome == .bool(true))
    }

    @Test(arguments: [
        (.divide(.checked), .min), (.remainder, 0),
    ] as [(IRBinaryOperator, Int64)])
    func `Int.min / -1 and Int.min % -1 never reach the results LLVM leaves undefined`(
        op: IRBinaryOperator, result: Int64,
    ) throws {
        // The optimiser computes the operation on the constants itself, and finds where LLVM leaves its result
        // undefined, whatever the host's hardware does with it.
        #expect(try folding(of: op, .min, -1) == .defined(result))
    }
}
