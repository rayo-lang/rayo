import LLVM
import RayoSource
import RayoSyntax

/// Emits the unary operators, and every binary operator but `&&` and `||`, on Int and Bool values into a function.
/// Integer operations panic or wrap where Rayo says they do, and so never reach LLVM's undefined cases.
struct OperatorEmitter {
    /// The function that a panic's blocks are appended to.
    private let llvmFunction: Function
    private let types: LLVMTypes
    /// The runtime's function that a panic calls.
    private let panic: Function

    init(into llvmFunction: Function, types: LLVMTypes, panic: Function) {
        self.llvmFunction = llvmFunction
        self.types = types
        self.panic = panic
    }

    /// Emits `op` on `operand` at the builder's position and returns its value. An operator that can panic leaves the
    /// builder in a new block. Throws where the IR gives `op` an operand of a type it doesn't take.
    func emit(_ op: UnaryOperator, on operand: AnyValue, at range: SourceRange,
              in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        switch op {
        // Negation subtracts an Int from 0.
        case .negate:
            let negated = try int(operand, op)
            return emitArithmetic(.subtract, types.int64.constant(0), negated, at: range, in: program).anyValue

        // `!` flips a Bool's one bit.
        case .not:
            let flipped = try bool(operand, op)
            return program.builder.xor(flipped, types.bool.constant(1)).anyValue
        }
    }

    /// Emits `left op right` at the builder's position and returns its value. An operator that can panic leaves the
    /// builder in a new block. Throws where the IR gives `op` an operand of a type it doesn't take.
    func emit(_ op: BinaryOperator, _ left: AnyValue, _ right: AnyValue, at range: SourceRange,
              in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        switch op {
        case .add: try emitArithmetic(.add, int(left, op), int(right, op), at: range, in: program).anyValue
        case .subtract: try emitArithmetic(.subtract, int(left, op), int(right, op), at: range, in: program).anyValue
        case .multiply: try emitArithmetic(.multiply, int(left, op), int(right, op), at: range, in: program).anyValue
        case .divide: try emitDivision(int(left, op), int(right, op), at: range, in: program).anyValue
        case .remainder: try emitRemainder(int(left, op), int(right, op), at: range, in: program).anyValue
        case .equal: try compare(.equal, op, left, right, with: program.builder).anyValue
        case .notEqual: try compare(.notEqual, op, left, right, with: program.builder).anyValue
        case .less: try compare(.signedLess, op, left, right, with: program.builder).anyValue
        case .lessEqual: try compare(.signedLessEqual, op, left, right, with: program.builder).anyValue
        case .greater: try compare(.signedGreater, op, left, right, with: program.builder).anyValue
        case .greaterEqual: try compare(.signedGreaterEqual, op, left, right, with: program.builder).anyValue
        case .and, .or: preconditionFailure("lowering turns '\(op.rawValue)' into branches")
        }
    }

    /// Emits `left op right`, which panics on overflow where overflow is checked and wraps where it isn't.
    private func emitArithmetic(_ op: OverflowingOperation, _ left: IntValue<I64>, _ right: IntValue<I64>,
                                at range: SourceRange, in program: borrowing ProgramEmitter) -> IntValue<I64> {
        // Where overflow isn't checked, the plain instruction wraps.
        guard program.build.checksOverflow else { return emitWrapping(op, left, right, with: program.builder) }

        // Where it is, the intrinsic flags an overflow beside the result, and an overflow panics. The intrinsic
        // returns a pair of an Int and a Bool, so its call always gives one.
        let intrinsic = program.module.intrinsic(named: op.intrinsicName, overloadedOn: types.int64)
        let call = program.builder.call(intrinsic, [left, right])!
        let pair = AggregateValue(call)!
        let overflowed = IntValue<I1>(program.builder.extractValue(from: pair, at: 1))!
        panic(if: overflowed, .overflow, at: range, in: program)
        return IntValue<I64>(program.builder.extractValue(from: pair, at: 0))!
    }

    private func emitWrapping(_ op: OverflowingOperation, _ left: IntValue<I64>, _ right: IntValue<I64>,
                              with builder: borrowing Builder) -> IntValue<I64> {
        switch op {
        case .add: builder.add(left, right)
        case .subtract: builder.subtract(left, right)
        case .multiply: builder.multiply(left, right)
        }
    }

    /// Emits `left / right`, which panics on a zero divisor, and on Int.min / -1 where overflow is checked; where it
    /// isn't, Int.min / -1 wraps.
    private func emitDivision(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                              in program: borrowing ProgramEmitter) -> IntValue<I64> {
        panic(ifZero: right, .divisionByZero, at: range, in: program)

        let isMinusOne = program.builder.compare(.equal, right, types.int64.constant(-1))

        // Where overflow is checked, Int.min / -1, the one quotient that overflows, panics.
        if program.build.checksOverflow {
            let isMin = program.builder.compare(.equal, left, types.int64.constant(.min))
            panic(if: program.builder.and(isMin, isMinusOne), .overflow, at: range, in: program)
        }

        // LLVM leaves Int.min / -1 undefined, so divide by -1 as by 1 and negate, which wraps Int.min to itself.
        let divisor = selectDivisor(right, replacingMinusOne: isMinusOne, with: program.builder)
        let quotient = program.builder.signedDivide(left, divisor)
        let negated = program.builder.subtract(types.int64.constant(0), quotient)
        return program.builder.select(isMinusOne, negated, quotient)
    }

    /// Emits `left % right`, which panics on a zero divisor.
    private func emitRemainder(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                               in program: borrowing ProgramEmitter) -> IntValue<I64> {
        panic(ifZero: right, .remainderByZero, at: range, in: program)

        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so a divisor of -1 becomes 1.
        let isMinusOne = program.builder.compare(.equal, right, types.int64.constant(-1))
        let divisor = selectDivisor(right, replacingMinusOne: isMinusOne, with: program.builder)
        return program.builder.signedRemainder(left, divisor)
    }

    /// Emits a divisor that is 1 where `isMinusOne` holds, and `right` elsewhere.
    private func selectDivisor(_ right: IntValue<I64>, replacingMinusOne isMinusOne: IntValue<I1>,
                               with builder: borrowing Builder) -> IntValue<I64> {
        builder.select(isMinusOne, types.int64.constant(1), right)
    }

    /// Emits the comparison of `left` and `right`, two Bools or two Ints, for `op`.
    private func compare(_ predicate: IntegerPredicate, _ op: BinaryOperator, _ left: AnyValue, _ right: AnyValue,
                         with builder: borrowing Builder) throws(LLVMError) -> IntValue<I1> {
        // A Bool compares as an `i1` with another Bool.
        if let left = IntValue<I1>(left) { return builder.compare(predicate, left, try bool(right, op)) }
        // An Int compares as an `i64` with another Int.
        if let left = IntValue<I64>(left) { return builder.compare(predicate, left, try int(right, op)) }
        // A value of any other type is neither, and compares with nothing.
        throw mismatch(op, given: left, takes: "i1 or i64")
    }

    private func panic(ifZero value: IntValue<I64>, _ reason: PanicReason, at range: SourceRange,
                       in program: borrowing ProgramEmitter) {
        panic(if: program.builder.compare(.equal, value, types.int64.constant(0)), reason, at: range, in: program)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private func panic(if condition: IntValue<I1>, _ reason: PanicReason, at range: SourceRange,
                       in program: borrowing ProgramEmitter) {
        // Split on the condition into two blocks appended at the function's end.
        let panics = program.context.appendBlock(named: "panic", to: llvmFunction)
        let continues = program.context.appendBlock(named: "continue", to: llvmFunction)
        program.builder.branch(if: condition, then: panics, else: continues)

        // The panic block reports the reason and the place, and never returns.
        program.builder.position(atEndOf: panics)
        let message = Array("\(program.sourcePath):\(range.start): panic: \(reason.rawValue)\n".utf8)
        let bytes = program.context.constant(bytes: message)
        let text = program.module.addGlobal(named: "rayo.panic_message", initializer: bytes)
        text.setConstant()
        text.setUnnamedAddress()
        program.builder.call(panic, [text.pointer, types.int64.constant(Int64(message.count))])
        program.builder.unreachable()

        program.builder.position(atEndOf: continues)
    }

    /// `value`, an operand of `op`, as an integer of `Width`. Throws where it is of another type, which the checker
    /// passes no IR with.
    private func operand<Width, Operator: RawRepresentable<String>>(
        _ value: AnyValue, of op: Operator, as width: Width.Type,
    ) throws(LLVMError) -> IntValue<Width> {
        // An operand of another type would reach LLVM only to be rejected, so it fails here, saying what it is.
        guard let operand = IntValue<Width>(value) else {
            throw mismatch(op, given: value, takes: "i\(Width.bitWidth)")
        }
        return operand
    }

    /// The error that says the IR gives `op` the operand `value`, where it takes a value of the type `expected`
    /// names.
    private func mismatch(
        _ op: some RawRepresentable<String>, given value: AnyValue, takes expected: String,
    ) -> LLVMError {
        let given = "an operand of type \(value.type.text)"
        return LLVMError(message: "the IR gives '\(op.rawValue)' \(given), where it takes \(expected)")
    }

    private func int(_ value: AnyValue, _ op: some RawRepresentable<String>) throws(LLVMError) -> IntValue<I64> {
        try operand(value, of: op, as: I64.self)
    }

    private func bool(_ value: AnyValue, _ op: some RawRepresentable<String>) throws(LLVMError) -> IntValue<I1> {
        try operand(value, of: op, as: I1.self)
    }
}

/// Why an operator panics, as its panic message says.
private enum PanicReason: String {
    case overflow = "integer overflow"
    case divisionByZero = "division by zero"
    case remainderByZero = "remainder by zero"
}

/// An integer operation that can overflow.
private enum OverflowingOperation: String {
    case add = "sadd"
    case subtract = "ssub"
    case multiply = "smul"

    /// The intrinsic that computes the operation and reports whether it overflowed.
    var intrinsicName: String { "llvm.\(rawValue).with.overflow" }
}
