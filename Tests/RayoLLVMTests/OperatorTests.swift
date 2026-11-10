import RayoSyntax
import Testing

/// The builds `rayoc` makes: a debug build, where overflow panics, and a release build, where it wraps.
private let builds: [OperatorModule.Build] = [.debug, .release]

@Suite("Operators on Int and Bool values")
struct OperatorTests {
    @Test("'+', '-' and '*' compute what they name, in every build", arguments: [
        (.add, 7, -5, 2), (.subtract, 7, -5, 12), (.multiply, 7, -5, -35),
    ] as [(BinaryOperator, Int64, Int64, Int64)], builds)
    func arithmetic(operation: (BinaryOperator, Int64, Int64, Int64), build: OperatorModule.Build) throws {
        let (op, left, right, result) = operation
        #expect(try outcome(of: op, left, right, in: build) == .int(result))
    }

    @Test("an overflowing '+', '-' or '*' panics where overflow is checked, and wraps where it isn't", arguments: [
        (.add, .max, 1, .min),
        (.subtract, .min, 1, .max),
        (.multiply, 1 << 62, 2, .min),
    ] as [(BinaryOperator, Int64, Int64, Int64)])
    func overflow(op: BinaryOperator, left: Int64, right: Int64, wrapped: Int64) throws {
        #expect(try outcome(of: op, left, right, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: op, left, right, in: .release) == .int(wrapped))
    }

    @Test("'-' negates an Int, in every build", arguments: builds)
    func negation(build: OperatorModule.Build) throws {
        #expect(try outcome(of: .negate, 5, in: build) == .int(-5))
    }

    @Test("negating Int.min panics where overflow is checked, and wraps to Int.min where it isn't")
    func overflowingNegation() throws {
        #expect(try outcome(of: .negate, .min, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: .negate, .min, in: .release) == .int(.min))
    }

    @Test("'/' rounds toward zero, in every build", arguments: [
        (7, 2, 3), (-7, 2, -3), (7, -2, -3), (-7, -2, 3), (5, -1, -5), (.max, -1, -.max),
        (.min, 2, -4_611_686_018_427_387_904),
    ] as [(Int64, Int64, Int64)], builds)
    func division(operands: (Int64, Int64, Int64), build: OperatorModule.Build) throws {
        let (left, right, quotient) = operands
        #expect(try outcome(of: .divide, left, right, in: build) == .int(quotient))
    }

    @Test("Int.min / -1 panics where overflow is checked, and wraps to Int.min where it isn't")
    func overflowingDivision() throws {
        #expect(try outcome(of: .divide, .min, -1, in: .debug) == .panics("integer overflow"))
        #expect(try outcome(of: .divide, .min, -1, in: .release) == .int(.min))
    }

    @Test("'%' takes the dividend's sign, and a remainder by -1 is 0, Int.min's too, in every build", arguments: [
        (7, 3, 1), (-7, 3, -1), (7, -3, 1), (-7, -3, -1), (7, -1, 0), (.min, -1, 0), (.min, 3, -2),
    ] as [(Int64, Int64, Int64)], builds)
    func remainder(operands: (Int64, Int64, Int64), build: OperatorModule.Build) throws {
        let (left, right, remainder) = operands
        #expect(try outcome(of: .remainder, left, right, in: build) == .int(remainder))
    }

    @Test("'/' and '%' by zero panic in every build", arguments: [
        (.divide, "division by zero"), (.remainder, "remainder by zero"),
    ] as [(BinaryOperator, String)], builds)
    func zeroDivisor(operation: (BinaryOperator, String), build: OperatorModule.Build) throws {
        let (op, reason) = operation
        #expect(try outcome(of: op, 7, 0, in: build) == .panics(reason))
    }

    @Test("a comparison of two Ints orders them as signed", arguments: [
        (.equal, [false, true, false]),
        (.notEqual, [true, false, true]),
        (.less, [true, false, false]),
        (.lessEqual, [true, true, false]),
        (.greater, [false, false, true]),
        (.greaterEqual, [false, true, true]),
    ] as [(BinaryOperator, [Bool])])
    func comparison(op: BinaryOperator, againstZero: [Bool]) throws {
        // Each operator compares -1, 0 and 1 against 0, which a comparison of unsigned values would get wrong.
        for (left, expected) in zip([-1, 0, 1] as [Int64], againstZero) {
            #expect(try outcome(of: op, left, 0, in: .debug) == .bool(expected))
        }
    }

    @Test("'==' and '!=' compare two Bools", arguments: [
        (true, true, true), (true, false, false), (false, true, false), (false, false, true),
    ])
    func boolEquality(left: Bool, right: Bool, equal: Bool) throws {
        #expect(try outcome(of: .equal, left, right) == .bool(equal))
        #expect(try outcome(of: .notEqual, left, right) == .bool(!equal))
    }

    @Test("'!' inverts a Bool", arguments: [(true, false), (false, true)])
    func not(operand: Bool, inverted: Bool) throws {
        #expect(try outcome(of: .not, operand) == .bool(inverted))
    }
}

/// Operators keep the results Rayo gives them, and their panics, through a release build's optimiser, which may
/// take an operation whose result LLVM leaves undefined never to happen, and would then give each expression
/// another result.
@Suite("Operators optimised as a release build is")
struct OptimizedOperatorTests {
    @Test("Int.max + 1 wraps below Int.max")
    func add() throws {
        #expect(try releaseOutcome(of: .max) { emit, a in emit(.less, emit(.add, a, 1), a) } == .bool(true))
    }

    @Test("Int.min - 1 wraps above Int.min")
    func subtract() throws {
        #expect(try releaseOutcome(of: .min) { emit, a in emit(.greater, emit(.subtract, a, 1), a) } == .bool(true))
    }

    @Test("Int.min * 2 wraps to 0")
    func multiply() throws {
        #expect(try releaseOutcome(of: .min) { emit, a in emit(.equal, emit(.multiply, a, 2), 0) } == .bool(true))
    }

    @Test("negating Int.min wraps to Int.min")
    func negate() throws {
        #expect(try releaseOutcome(of: .min) { emit, a in emit(.equal, emit(.negate, a), a) } == .bool(true))
    }

    @Test("Int.min / -1 wraps to Int.min, where the optimiser knows the divisor")
    func divideByKnownMinusOne() throws {
        #expect(try releaseOutcome(of: .min) { emit, a in emit(.equal, emit(.divide, a, -1), a) } == .bool(true))
    }

    @Test("7 / 2 rounds to 3, the quotient of a division with a remainder")
    func inexactDivision() throws {
        #expect(try releaseOutcome(of: 7) { emit, a in emit(.equal, emit(.divide, a, 2), 3) } == .bool(true))
    }

    @Test("Int.min / -1 and Int.min % -1 never reach the results LLVM leaves undefined", arguments: [
        (.divide, .min), (.remainder, 0),
    ] as [(BinaryOperator, Int64)])
    func minByMinusOneIsDefined(op: BinaryOperator, result: Int64) throws {
        // The optimiser computes the operation on the constants itself, and finds where LLVM leaves its result
        // undefined, whatever the host's hardware does with it.
        #expect(try folding(of: op, .min, -1) == .defined(result))
    }
}
