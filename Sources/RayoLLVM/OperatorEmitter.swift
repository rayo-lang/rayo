import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits the IR's operators on scalar values into a function, each in its operands' number format, and the
/// conversions between the integer types. Integer operations panic or wrap where Rayo says they do, and so never reach
/// LLVM's undefined cases.
struct OperatorEmitter {
    private let types: LLVMTypes
    /// The function's panics, which an operation emits where it fails.
    private let panics: PanicEmitter

    init(types: LLVMTypes, panics: PanicEmitter) {
        self.types = types
        self.panics = panics
    }

    /// Emits `op` on `operand`, a value of `type`, at the builder's position and returns its value. An operator that
    /// can panic leaves the builder in a new block. `op` must take an operand of `type`.
    func emit(_ op: IRUnaryOperator, on operand: AnyValue, of type: RayoType, at range: SourceRange,
              in program: borrowing ProgramEmitter) -> AnyValue {
        let format = format(of: type)
        let value = format.value(operand)

        return switch op {
        // Negation subtracts an integer from 0, so it overflows for every unsigned integer but 0.
        case .negate(let mode):
            emitArithmetic(.subtract, mode, format, format.constant(0), value, at: range, in: program).anyValue

        // `!` flips a Bool's one bit.
        case .not:
            program.builder.xor(value, format.constant(1)).anyValue
        }
    }

    /// Emits `left op right`, two values of `type`, at the builder's position and returns its value. An operator that
    /// can panic leaves the builder in a new block. `op` must take operands of `type`.
    func emit(_ op: IRBinaryOperator, _ left: AnyValue, _ right: AnyValue, of type: RayoType, at range: SourceRange,
              in program: borrowing ProgramEmitter) -> AnyValue {
        let format = format(of: type)
        let (left, right) = (format.value(left), format.value(right))

        return switch op {
        // Arithmetic panics where Rayo says it does.
        case .add(let mode):
            emitArithmetic(.add, mode, format, left, right, at: range, in: program).anyValue
        case .subtract(let mode):
            emitArithmetic(.subtract, mode, format, left, right, at: range, in: program).anyValue
        case .multiply(let mode):
            emitArithmetic(.multiply, mode, format, left, right, at: range, in: program).anyValue
        case .divide(let mode):
            emitDivision(mode, format, left, right, at: range, in: program).anyValue
        case .remainder:
            emitRemainder(format, left, right, at: range, in: program).anyValue

        // A comparison orders its operands as their signedness says, and a Bool compares as its bit.
        case .equal: compare(.equal, left, right, with: program.builder)
        case .notEqual: compare(.notEqual, left, right, with: program.builder)
        case .less: compare(format.signedness.less, left, right, with: program.builder)
        case .lessEqual: compare(format.signedness.lessEqual, left, right, with: program.builder)
        case .greater: compare(format.signedness.greater, left, right, with: program.builder)
        case .greaterEqual: compare(format.signedness.greaterEqual, left, right, with: program.builder)
        }
    }

    /// Emits the conversion of `value`, an integer of type `source`, to the integer type `target`, at the builder's
    /// position, and returns the converted value. The conversion keeps the low bits of the value that `target` holds,
    /// and panics where the build checks overflow and `target` can't hold the value; it then leaves the builder in a
    /// new block.
    func emitConversion(of value: AnyValue, from source: ScalarType, to target: ScalarType, at range: SourceRange,
                        in program: borrowing ProgramEmitter) -> AnyValue {
        let from = types.format(of: source)
        let to = types.format(of: target)
        let integer = from.value(value)

        // Two types of one format hold the same values, so the value is kept as it is.
        guard from != to else { return value }
        let converted = resize(integer, from: from, to: to, with: program.builder)

        // A value that `target` can't hold panics where the build checks overflow.
        if program.build.checksOverflow {
            let isLost = emitLoss(of: integer, from: from, in: converted, to: to, with: program.builder)
            panics.panic(if: isLost, .overflow, at: range, in: program)
        }
        return converted.anyValue
    }

    /// Emits whether `converted`, `value` converted from format `from` to format `to`, lost the value: where
    /// converting it back changes it, or, between a signed and an unsigned format, where the signed one of the two is
    /// negative, since the unsigned format reads that value's bits as a large value.
    private func emitLoss(of value: AnyIntValue, from: NumberFormat, in converted: AnyIntValue, to: NumberFormat,
                          with builder: borrowing Builder) -> IntValue<I1> {
        let back = resize(converted, from: to, to: from, with: builder)
        let changed = builder.compare(.notEqual, back, value)
        guard from.signedness != to.signedness else { return changed }

        let (signed, signedFormat) = from.signedness == .signed ? (value, from) : (converted, to)
        let isNegative = builder.compare(.signedLess, signed, signedFormat.constant(0))
        return builder.or(changed, isNegative)
    }

    /// The number format of `type`, which must be a scalar type.
    private func format(of type: RayoType) -> NumberFormat {
        // The verifier passes no IR that gives an operator an operand that isn't a scalar.
        guard case .scalar(let scalar) = type else { preconditionFailure("the IR gives an operator a \(type)") }
        return types.format(of: scalar)
    }

    /// `value`, of format `from`, as an integer of format `to`: its low bits where `to` is narrower, and where it is
    /// wider, the value padded with zeros or, where `from` is signed, with copies of its sign.
    private func resize(_ value: AnyIntValue, from: NumberFormat, to: NumberFormat,
                        with builder: borrowing Builder) -> AnyIntValue {
        let (fromWidth, toWidth) = (from.type.bitWidth, to.type.bitWidth)
        if toWidth < fromWidth { return builder.truncate(value, to: to.type) }
        if toWidth == fromWidth { return value }
        return switch from.signedness {
        case .signed: builder.signExtend(value, to: to.type)
        case .unsigned: builder.zeroExtend(value, to: to.type)
        }
    }

    /// Emits `left op right` on two integers of `format`, which panics on overflow where `mode` and the build check
    /// it, and wraps elsewhere.
    private func emitArithmetic(
        _ op: OverflowingOperation, _ mode: OverflowMode, _ format: NumberFormat, _ left: AnyIntValue,
        _ right: AnyIntValue, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) -> AnyIntValue {
        // Where overflow isn't checked, the plain instruction wraps.
        guard mode.panics(in: program.build) else { return emitWrapping(op, left, right, with: program.builder) }

        // Where it is, the intrinsic for the operands' signedness flags an overflow beside the result, and an
        // overflow panics. The intrinsic returns a pair of an integer and a Bool, so its call always gives one.
        let name = op.intrinsicName(for: format.signedness)
        let intrinsic = program.module.intrinsic(named: name, overloadedOn: format.type)
        let call = program.builder.call(intrinsic, [left, right])!
        let pair = AggregateValue(call)!
        let overflowed = IntValue<I1>(program.builder.extractValue(from: pair, at: 1))!
        panics.panic(if: overflowed, .overflow, at: range, in: program)
        return format.value(program.builder.extractValue(from: pair, at: 0))
    }

    private func emitWrapping(_ op: OverflowingOperation, _ left: AnyIntValue, _ right: AnyIntValue,
                              with builder: borrowing Builder) -> AnyIntValue {
        switch op {
        case .add: builder.add(left, right)
        case .subtract: builder.subtract(left, right)
        case .multiply: builder.multiply(left, right)
        }
    }

    /// Emits `left / right` on two integers of `format`, which panics on a zero divisor.
    private func emitDivision(
        _ mode: OverflowMode, _ format: NumberFormat, _ left: AnyIntValue, _ right: AnyIntValue,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) -> AnyIntValue {
        panic(ifZero: right, of: format, .divisionByZero, at: range, in: program)

        // No unsigned quotient overflows.
        guard format.signedness == .signed else { return program.builder.unsignedDivide(left, right) }
        return emitSignedDivision(mode, format, left, right, at: range, in: program)
    }

    /// Emits `left / right` on two signed integers of `format`, whose divisor isn't zero, which panics on the most
    /// negative value divided by -1 where `mode` and the build check overflow; elsewhere, that quotient wraps.
    private func emitSignedDivision(
        _ mode: OverflowMode, _ format: NumberFormat, _ left: AnyIntValue, _ right: AnyIntValue,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) -> AnyIntValue {
        let isMinusOne = program.builder.compare(.equal, right, format.constant(-1))

        // Where overflow is checked, the most negative value divided by -1, the one quotient that overflows, panics.
        if mode.panics(in: program.build) {
            let isMin = program.builder.compare(.equal, left, mostNegative(of: format))
            panics.panic(if: program.builder.and(isMin, isMinusOne), .overflow, at: range, in: program)
        }

        // LLVM leaves that quotient undefined, so divide by -1 as by 1 and negate, which wraps the most negative value
        // to itself.
        let divisor = selectDivisor(right, of: format, replacingMinusOne: isMinusOne, with: program.builder)
        let quotient = program.builder.signedDivide(left, divisor)
        let negated = program.builder.subtract(format.constant(0), quotient)
        return program.builder.select(isMinusOne, negated, quotient)
    }

    /// Emits `left % right` on two integers of `format`, which panics on a zero divisor.
    private func emitRemainder(
        _ format: NumberFormat, _ left: AnyIntValue, _ right: AnyIntValue, at range: SourceRange,
        in program: borrowing ProgramEmitter,
    ) -> AnyIntValue {
        panic(ifZero: right, of: format, .remainderByZero, at: range, in: program)
        guard format.signedness == .signed else { return program.builder.unsignedRemainder(left, right) }

        // Every remainder by -1 is 0, but LLVM leaves the most negative value's undefined, so a divisor of -1 becomes
        // 1.
        let isMinusOne = program.builder.compare(.equal, right, format.constant(-1))
        let divisor = selectDivisor(right, of: format, replacingMinusOne: isMinusOne, with: program.builder)
        return program.builder.signedRemainder(left, divisor)
    }

    /// The most negative value of `format`, a signed format: its top bit alone.
    private func mostNegative(of format: NumberFormat) -> AnyIntValue {
        format.constant(-(Int128(1) << (format.type.bitWidth - 1)))
    }

    /// Emits a divisor that is 1 where `isMinusOne` holds, and `right` elsewhere.
    private func selectDivisor(
        _ right: AnyIntValue, of format: NumberFormat, replacingMinusOne isMinusOne: IntValue<I1>,
        with builder: borrowing Builder,
    ) -> AnyIntValue {
        builder.select(isMinusOne, format.constant(1), right)
    }

    /// Emits the comparison of `left` and `right` for `predicate`, and returns the Bool it gives.
    private func compare(_ predicate: IntegerPredicate, _ left: AnyIntValue, _ right: AnyIntValue,
                         with builder: borrowing Builder) -> AnyValue {
        builder.compare(predicate, left, right).anyValue
    }

    /// Branches to a panic for `reason` where `value`, of `format`, is zero, and continues in a new block otherwise.
    private func panic(ifZero value: AnyIntValue, of format: NumberFormat, _ reason: PanicReason,
                       at range: SourceRange, in program: borrowing ProgramEmitter) {
        let isZero = program.builder.compare(.equal, value, format.constant(0))
        panics.panic(if: isZero, reason, at: range, in: program)
    }
}

private extension OverflowMode {
    /// Whether an operation in this mode panics on overflow in `build`, where otherwise it wraps.
    func panics(in build: Build) -> Bool {
        self == .checked && build.checksOverflow
    }
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
