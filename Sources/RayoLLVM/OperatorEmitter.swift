import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits the IR's operators on integer and Bool values into a function, each as its operands' type says, and the
/// conversions between the integer types. Integer operations panic or wrap where Rayo says they do, and so never
/// reach LLVM's undefined cases.
struct OperatorEmitter {
    /// The function that a panic's blocks are appended to.
    private let llvmFunction: Function
    private let types: LLVMTypes

    init(into llvmFunction: Function, types: LLVMTypes) {
        self.llvmFunction = llvmFunction
        self.types = types
    }

    /// Emits `op` on `operand`, a value of `type`, at the builder's position and returns its value. An operator that
    /// can panic leaves the builder in a new block. `op` must take an operand of `type`.
    func emit(_ op: IRUnaryOperator, on operand: AnyValue, of type: RayoType, at range: SourceRange,
              in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        switch (op, type) {
        // Negation subtracts an integer from 0, so it overflows for every UInt but 0.
        case (.negate(let mode), .int), (.negate(let mode), .uint):
            try emitArithmetic(.subtract, mode, Signedness(of: type), types.int64.constant(0), int(operand),
                               at: range, in: program).anyValue

        // `!` flips a Bool's one bit.
        case (.not, .bool):
            program.builder.xor(bool(operand), types.bool.constant(1)).anyValue

        // The verifier passes no IR that gives an operator an operand of another type.
        default:
            preconditionFailure("the IR gives '\(op)' an operand of type \(type)")
        }
    }

    /// Emits `left op right`, two values of `type`, at the builder's position and returns its value. An operator that
    /// can panic leaves the builder in a new block. `op` must take operands of `type`.
    func emit(_ op: IRBinaryOperator, _ left: AnyValue, _ right: AnyValue, of type: RayoType, at range: SourceRange,
              in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        switch (op, type) {
        // Two integers compute and compare as their type's signedness says.
        case (_, .int), (_, .uint):
            try emit(op, int(left), int(right), Signedness(of: type), at: range, in: program)

        // Two Bools compare as bits.
        case (.equal, .bool): compare(.equal, bool(left), bool(right), with: program.builder)
        case (.notEqual, .bool): compare(.notEqual, bool(left), bool(right), with: program.builder)

        // The verifier passes no IR that gives an operator operands of another type.
        default:
            preconditionFailure("the IR gives '\(op)' operands of type \(type)")
        }
    }

    /// Emits the conversion of `value`, an Int or a UInt, to the other of the two, at the builder's position, and
    /// returns the converted value. The conversion keeps the value's bits, and panics where the build checks overflow
    /// and the other type can't hold the value; it then leaves the builder in a new block.
    func emitConversion(of value: AnyValue, at range: SourceRange,
                        in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        // The values that only one of the two types holds are those whose top bit is set: a negative Int, and a UInt
        // above Int.max. Read as an Int, each of them is negative.
        if program.build.checksOverflow {
            let isNegative = program.builder.compare(.signedLess, int(value), types.int64.constant(0))
            try panic(if: isNegative, .overflow, at: range, in: program)
        }
        return value
    }

    /// Emits `left op right` on two integers whose type has `signedness`, and returns its value.
    private func emit(
        _ op: IRBinaryOperator, _ left: IntValue<I64>, _ right: IntValue<I64>, _ signedness: Signedness,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) -> AnyValue {
        switch (op, signedness) {
        // Arithmetic panics where Rayo says it does.
        case (.add(let mode), _):
            try emitArithmetic(.add, mode, signedness, left, right, at: range, in: program).anyValue
        case (.subtract(let mode), _):
            try emitArithmetic(.subtract, mode, signedness, left, right, at: range, in: program).anyValue
        case (.multiply(let mode), _):
            try emitArithmetic(.multiply, mode, signedness, left, right, at: range, in: program).anyValue
        case (.divide(let mode), .signed):
            try emitSignedDivision(mode, left, right, at: range, in: program).anyValue
        case (.divide, .unsigned):
            try emitUnsignedDivision(left, right, at: range, in: program).anyValue
        case (.remainder, .signed):
            try emitSignedRemainder(left, right, at: range, in: program).anyValue
        case (.remainder, .unsigned):
            try emitUnsignedRemainder(left, right, at: range, in: program).anyValue

        // A comparison orders its operands as their signedness says.
        case (.equal, _): compare(.equal, left, right, with: program.builder)
        case (.notEqual, _): compare(.notEqual, left, right, with: program.builder)
        case (.less, _): compare(signedness.less, left, right, with: program.builder)
        case (.lessEqual, _): compare(signedness.lessEqual, left, right, with: program.builder)
        case (.greater, _): compare(signedness.greater, left, right, with: program.builder)
        case (.greaterEqual, _): compare(signedness.greaterEqual, left, right, with: program.builder)
        }
    }

    /// Emits `left op right` on two integers whose type has `signedness`, which panics on overflow where `mode` and
    /// the build check it, and wraps elsewhere.
    private func emitArithmetic(
        _ op: OverflowingOperation, _ mode: OverflowMode, _ signedness: Signedness, _ left: IntValue<I64>,
        _ right: IntValue<I64>, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) -> IntValue<I64> {
        // Where overflow isn't checked, the plain instruction wraps.
        guard mode.panics(in: program.build) else { return emitWrapping(op, left, right, with: program.builder) }

        // Where it is, the intrinsic for the operands' signedness flags an overflow beside the result, and an
        // overflow panics. The intrinsic returns a pair of an integer and a Bool, so its call always gives one.
        let intrinsic = program.module.intrinsic(named: op.intrinsicName(for: signedness), overloadedOn: types.int64)
        let call = program.builder.call(intrinsic, [left, right])!
        let pair = AggregateValue(call)!
        let overflowed = IntValue<I1>(program.builder.extractValue(from: pair, at: 1))!
        try panic(if: overflowed, .overflow, at: range, in: program)
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

    /// Emits `left / right` on two Ints, which panics on a zero divisor, and on Int.min / -1 where `mode` and the
    /// build check overflow; elsewhere, Int.min / -1 wraps.
    private func emitSignedDivision(
        _ mode: OverflowMode, _ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
        in program: borrowing ProgramEmitter,
    ) throws(LLVMError) -> IntValue<I64> {
        try panic(ifZero: right, .divisionByZero, at: range, in: program)

        let isMinusOne = program.builder.compare(.equal, right, types.int64.constant(-1))

        // Where overflow is checked, Int.min / -1, the one quotient that overflows, panics.
        if mode.panics(in: program.build) {
            let isMin = program.builder.compare(.equal, left, types.int64.constant(.min))
            try panic(if: program.builder.and(isMin, isMinusOne), .overflow, at: range, in: program)
        }

        // LLVM leaves Int.min / -1 undefined, so divide by -1 as by 1 and negate, which wraps Int.min to itself.
        let divisor = selectDivisor(right, replacingMinusOne: isMinusOne, with: program.builder)
        let quotient = program.builder.signedDivide(left, divisor)
        let negated = program.builder.subtract(types.int64.constant(0), quotient)
        return program.builder.select(isMinusOne, negated, quotient)
    }

    /// Emits `left / right` on two UInts, which panics on a zero divisor. No UInt quotient overflows.
    private func emitUnsignedDivision(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                                      in program: borrowing ProgramEmitter) throws(LLVMError) -> IntValue<I64> {
        try panic(ifZero: right, .divisionByZero, at: range, in: program)
        return program.builder.unsignedDivide(left, right)
    }

    /// Emits `left % right` on two Ints, which panics on a zero divisor.
    private func emitSignedRemainder(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                                     in program: borrowing ProgramEmitter) throws(LLVMError) -> IntValue<I64> {
        try panic(ifZero: right, .remainderByZero, at: range, in: program)

        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so a divisor of -1 becomes 1.
        let isMinusOne = program.builder.compare(.equal, right, types.int64.constant(-1))
        let divisor = selectDivisor(right, replacingMinusOne: isMinusOne, with: program.builder)
        return program.builder.signedRemainder(left, divisor)
    }

    /// Emits `left % right` on two UInts, which panics on a zero divisor.
    private func emitUnsignedRemainder(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                                       in program: borrowing ProgramEmitter) throws(LLVMError) -> IntValue<I64> {
        try panic(ifZero: right, .remainderByZero, at: range, in: program)
        return program.builder.unsignedRemainder(left, right)
    }

    /// Emits a divisor that is 1 where `isMinusOne` holds, and `right` elsewhere.
    private func selectDivisor(_ right: IntValue<I64>, replacingMinusOne isMinusOne: IntValue<I1>,
                               with builder: borrowing Builder) -> IntValue<I64> {
        builder.select(isMinusOne, types.int64.constant(1), right)
    }

    /// Emits the comparison of `left` and `right` for `predicate`, and returns the Bool it gives.
    private func compare<Width>(_ predicate: IntegerPredicate, _ left: IntValue<Width>, _ right: IntValue<Width>,
                                with builder: borrowing Builder) -> AnyValue {
        builder.compare(predicate, left, right).anyValue
    }

    private func panic(ifZero value: IntValue<I64>, _ reason: PanicReason, at range: SourceRange,
                       in program: borrowing ProgramEmitter) throws(LLVMError) {
        let isZero = program.builder.compare(.equal, value, types.int64.constant(0))
        try panic(if: isZero, reason, at: range, in: program)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private func panic(if condition: IntValue<I1>, _ reason: PanicReason, at range: SourceRange,
                       in program: borrowing ProgramEmitter) throws(LLVMError) {
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
        let panic = try program.runtimeFunction(named: "rayo.panic")
        program.builder.call(panic, [text.pointer, types.int64.constant(Int64(message.count))])
        program.builder.unreachable()

        program.builder.position(atEndOf: continues)
    }

    /// `value`, an Int or a UInt, as LLVM holds one.
    private func int(_ value: AnyValue) -> IntValue<I64> {
        // The verifier passes no IR that gives an integer's operator a value of another type.
        guard let int = IntValue<I64>(value) else { preconditionFailure("an integer is held as an i64") }
        return int
    }

    /// `value`, a Bool, as LLVM holds one.
    private func bool(_ value: AnyValue) -> IntValue<I1> {
        // The verifier passes no IR that gives a Bool's operator a value of another type.
        guard let bool = IntValue<I1>(value) else { preconditionFailure("a Bool is held as an i1") }
        return bool
    }
}

private extension OverflowMode {
    /// Whether an operation in this mode panics on overflow in `build`, where otherwise it wraps.
    func panics(in build: Build) -> Bool {
        self == .checked && build.checksOverflow
    }
}

/// Why an operator panics, as its panic message says.
private enum PanicReason: String {
    case overflow = "integer overflow"
    case divisionByZero = "division by zero"
    case remainderByZero = "remainder by zero"
}

/// How an integer type's operations read its bits: as a two's complement value, which may be negative, or as one
/// that can't be.
private enum Signedness {
    case signed
    case unsigned

    /// The signedness of `type`, which must be an integer type.
    init(of type: RayoType) {
        switch type {
        case .int: self = .signed
        case .uint: self = .unsigned
        case .bool, .void, .structure, .array: preconditionFailure("\(type) isn't an integer type")
        }
    }

    /// The predicates that order two integers of this signedness as `<`, `<=`, `>` and `>=` do.
    var less: IntegerPredicate { self == .signed ? .signedLess : .unsignedLess }
    var lessEqual: IntegerPredicate { self == .signed ? .signedLessEqual : .unsignedLessEqual }
    var greater: IntegerPredicate { self == .signed ? .signedGreater : .unsignedGreater }
    var greaterEqual: IntegerPredicate { self == .signed ? .signedGreaterEqual : .unsignedGreaterEqual }
}

/// An integer operation that can overflow.
private enum OverflowingOperation: String {
    case add
    case subtract = "sub"
    case multiply = "mul"

    /// The intrinsic that computes the operation on integers of `signedness`, and reports whether it overflowed.
    func intrinsicName(for signedness: Signedness) -> String {
        let prefix = switch signedness {
        case .signed: "s"
        case .unsigned: "u"
        }
        return "llvm.\(prefix)\(rawValue).with.overflow"
    }
}
