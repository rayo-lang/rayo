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
    /// builder in a new block.
    func emit(_ op: UnaryOperator, on operand: AnyValue, at range: SourceRange,
              in program: borrowing ProgramEmitter) -> AnyValue {
        switch op {
        case .negate: emitArithmetic(.subtract, types.int64.constant(0), int(operand), at: range, in: program).anyValue
        case .not: program.builder.xor(bool(operand), types.bool.constant(1)).anyValue
        }
    }

    /// Emits `left op right` at the builder's position and returns its value. An operator that can panic leaves the
    /// builder in a new block.
    func emit(_ op: BinaryOperator, _ left: AnyValue, _ right: AnyValue, at range: SourceRange,
              in program: borrowing ProgramEmitter) -> AnyValue {
        switch op {
        case .add: emitArithmetic(.add, int(left), int(right), at: range, in: program).anyValue
        case .subtract: emitArithmetic(.subtract, int(left), int(right), at: range, in: program).anyValue
        case .multiply: emitArithmetic(.multiply, int(left), int(right), at: range, in: program).anyValue
        case .divide: emitDivision(int(left), int(right), at: range, in: program).anyValue
        case .remainder: emitRemainder(int(left), int(right), at: range, in: program).anyValue
        case .equal: compare(.equal, left, right, with: program.builder).anyValue
        case .notEqual: compare(.notEqual, left, right, with: program.builder).anyValue
        case .less: compare(.signedLess, left, right, with: program.builder).anyValue
        case .lessEqual: compare(.signedLessEqual, left, right, with: program.builder).anyValue
        case .greater: compare(.signedGreater, left, right, with: program.builder).anyValue
        case .greaterEqual: compare(.signedGreaterEqual, left, right, with: program.builder).anyValue
        case .and, .or: preconditionFailure("lowering turns '\(op.rawValue)' into branches")
        }
    }

    /// Emits `left op right`, which panics on overflow where overflow is checked and wraps where it isn't.
    private func emitArithmetic(_ op: OverflowingOperation, _ left: IntValue<I64>, _ right: IntValue<I64>,
                                at range: SourceRange, in program: borrowing ProgramEmitter) -> IntValue<I64> {
        // Where overflow isn't checked, the plain instruction wraps.
        guard program.checksOverflow else { return emitWrapping(op, left, right, with: program.builder) }

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
        if program.checksOverflow {
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

    /// Emits the comparison of `left` and `right`, two Bools or two Ints.
    private func compare(_ predicate: IntegerPredicate, _ left: AnyValue, _ right: AnyValue,
                         with builder: borrowing Builder) -> IntValue<I1> {
        // Bools compare as `i1`s.
        if let left = IntValue<I1>(left) { return builder.compare(predicate, left, bool(right)) }
        // Everything else compares as `i64`s.
        return builder.compare(predicate, int(left), int(right))
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

    /// `value` as an integer of `Width`, which the checker makes every operand of an operator on Ints or on Bools.
    /// LLVM's verifier rejects a module where one isn't.
    private func operand<Width>(_ value: AnyValue, as width: Width.Type) -> IntValue<Width> {
        IntValue(unchecked: value.ref)
    }

    private func int(_ value: AnyValue) -> IntValue<I64> {
        operand(value, as: I64.self)
    }

    private func bool(_ value: AnyValue) -> IntValue<I1> {
        operand(value, as: I1.self)
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
