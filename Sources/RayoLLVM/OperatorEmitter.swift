import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits the IR's operators on Int and Bool values into a function, each as its operands' type says. Integer
/// operations panic or wrap where Rayo says they do, and so never reach LLVM's undefined cases.
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
        // Negation subtracts an Int from 0.
        case (.negate(let mode), .int):
            try emitArithmetic(.subtract, mode, types.int64.constant(0), int(operand), at: range, in: program).anyValue

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
        // Arithmetic computes on two Ints, and panics where Rayo says it does.
        case (.add(let mode), .int):
            try emitArithmetic(.add, mode, int(left), int(right), at: range, in: program).anyValue
        case (.subtract(let mode), .int):
            try emitArithmetic(.subtract, mode, int(left), int(right), at: range, in: program).anyValue
        case (.multiply(let mode), .int):
            try emitArithmetic(.multiply, mode, int(left), int(right), at: range, in: program).anyValue
        case (.divide(let mode), .int):
            try emitDivision(mode, int(left), int(right), at: range, in: program).anyValue
        case (.remainder, .int):
            try emitRemainder(int(left), int(right), at: range, in: program).anyValue

        // Two Ints compare as signed integers, and two Bools as bits.
        case (.equal, .int): compare(.equal, int(left), int(right), with: program.builder)
        case (.notEqual, .int): compare(.notEqual, int(left), int(right), with: program.builder)
        case (.less, .int): compare(.signedLess, int(left), int(right), with: program.builder)
        case (.lessEqual, .int): compare(.signedLessEqual, int(left), int(right), with: program.builder)
        case (.greater, .int): compare(.signedGreater, int(left), int(right), with: program.builder)
        case (.greaterEqual, .int): compare(.signedGreaterEqual, int(left), int(right), with: program.builder)
        case (.equal, .bool): compare(.equal, bool(left), bool(right), with: program.builder)
        case (.notEqual, .bool): compare(.notEqual, bool(left), bool(right), with: program.builder)

        // The verifier passes no IR that gives an operator operands of another type.
        default:
            preconditionFailure("the IR gives '\(op)' operands of type \(type)")
        }
    }

    /// Emits `left op right`, which panics on overflow where `mode` and the build check it, and wraps elsewhere.
    private func emitArithmetic(
        _ op: OverflowingOperation, _ mode: OverflowMode, _ left: IntValue<I64>, _ right: IntValue<I64>,
        at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) -> IntValue<I64> {
        // Where overflow isn't checked, the plain instruction wraps.
        guard mode.panics(in: program.build) else { return emitWrapping(op, left, right, with: program.builder) }

        // Where it is, the intrinsic flags an overflow beside the result, and an overflow panics. The intrinsic
        // returns a pair of an Int and a Bool, so its call always gives one.
        let intrinsic = program.module.intrinsic(named: op.intrinsicName, overloadedOn: types.int64)
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

    /// Emits `left / right`, which panics on a zero divisor, and on Int.min / -1 where `mode` and the build check
    /// overflow; elsewhere, Int.min / -1 wraps.
    private func emitDivision(
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

    /// Emits `left % right`, which panics on a zero divisor.
    private func emitRemainder(_ left: IntValue<I64>, _ right: IntValue<I64>, at range: SourceRange,
                               in program: borrowing ProgramEmitter) throws(LLVMError) -> IntValue<I64> {
        try panic(ifZero: right, .remainderByZero, at: range, in: program)

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

    /// `value`, an Int, as LLVM holds one.
    private func int(_ value: AnyValue) -> IntValue<I64> {
        // The verifier passes no IR that gives an Int's operator a value of another type.
        guard let int = IntValue<I64>(value) else { preconditionFailure("an Int is held as an i64") }
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

/// An integer operation that can overflow.
private enum OverflowingOperation: String {
    case add = "sadd"
    case subtract = "ssub"
    case multiply = "smul"

    /// The intrinsic that computes the operation and reports whether it overflowed.
    var intrinsicName: String { "llvm.\(rawValue).with.overflow" }
}
