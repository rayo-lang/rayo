internal import CLLVM
import RayoSource
import RayoSyntax

/// Emits the unary operators, and every binary operator but `&&` and `||`, on Int and Bool values into a function.
/// Integer operations panic or wrap where Rayo says they do, and so never reach LLVM's undefined cases.
struct OperatorEmitter {
    private let program: ProgramEmitter
    /// The function that a panic's blocks are appended to.
    private let llvmFunction: LLVMValueRef

    init(program: ProgramEmitter, into llvmFunction: LLVMValueRef) {
        self.program = program
        self.llvmFunction = llvmFunction
    }

    private var module: ModuleBuilder { program.module }
    private var builder: LLVMBuilderRef { module.builder }

    /// Emits `op` on `operand` at the builder's position and returns its value. An operator that can panic leaves the
    /// builder in a new block.
    func emit(_ op: UnaryOperator, on operand: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .negate: return emitArithmetic(.subtract, module.constant(0), operand, at: range)
        case .not: return LLVMBuildXor(builder, operand, module.constant(true), "")
        }
    }

    /// Emits `left op right` at the builder's position and returns its value. An operator that can panic leaves the
    /// builder in a new block.
    func emit(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: LLVMValueRef,
              at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .add: return emitArithmetic(.add, left, right, at: range)
        case .subtract: return emitArithmetic(.subtract, left, right, at: range)
        case .multiply: return emitArithmetic(.multiply, left, right, at: range)
        case .divide: return emitDivision(left, right, at: range)
        case .remainder: return emitRemainder(left, right, at: range)
        case .equal: return compare(LLVMIntEQ, left, right)
        case .notEqual: return compare(LLVMIntNE, left, right)
        case .less: return compare(LLVMIntSLT, left, right)
        case .lessEqual: return compare(LLVMIntSLE, left, right)
        case .greater: return compare(LLVMIntSGT, left, right)
        case .greaterEqual: return compare(LLVMIntSGE, left, right)
        case .and, .or: preconditionFailure("lowering turns '\(op.rawValue)' into branches")
        }
    }

    /// Emits `left op right`, which panics on overflow where overflow is checked and wraps where it isn't.
    private func emitArithmetic(_ op: OverflowingOperation, _ left: LLVMValueRef, _ right: LLVMValueRef,
                                at range: SourceRange) -> LLVMValueRef {
        // Where overflow isn't checked, the plain instruction wraps.
        guard program.checksOverflow else { return emitWrapping(op, left, right) }

        // Where it is, the intrinsic flags an overflow beside the result, and an overflow panics.
        let pair = module.call(module.intrinsic(op.intrinsicName, overloadedOn: module.int64), [left, right])
        panic(if: LLVMBuildExtractValue(builder, pair, 1, ""), .overflow, at: range)
        return LLVMBuildExtractValue(builder, pair, 0, "")
    }

    private func emitWrapping(_ op: OverflowingOperation, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        switch op {
        case .add: return LLVMBuildAdd(builder, left, right, "")
        case .subtract: return LLVMBuildSub(builder, left, right, "")
        case .multiply: return LLVMBuildMul(builder, left, right, "")
        }
    }

    /// Emits `left / right`, which panics on a zero divisor, and on Int.min / -1 where overflow is checked; where it
    /// isn't, Int.min / -1 wraps.
    private func emitDivision(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        panic(ifZero: right, .divisionByZero, at: range)

        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))

        // Where overflow is checked, Int.min / -1, the one quotient that overflows, panics.
        if program.checksOverflow {
            let isMin = compare(LLVMIntEQ, left, module.constant(.min))
            panic(if: LLVMBuildAnd(builder, isMin, isMinusOne, ""), .overflow, at: range)
        }

        // LLVM leaves Int.min / -1 undefined, so divide by -1 as by 1 and negate, which wraps Int.min to itself.
        let quotient = LLVMBuildSDiv(builder, left, selectDivisor(right, replacingMinusOne: isMinusOne), "")
        let negated = LLVMBuildSub(builder, module.constant(0), quotient, "")
        return LLVMBuildSelect(builder, isMinusOne, negated, quotient, "")
    }

    /// Emits `left % right`, which panics on a zero divisor.
    private func emitRemainder(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        panic(ifZero: right, .remainderByZero, at: range)

        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so a divisor of -1 becomes 1.
        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))
        return LLVMBuildSRem(builder, left, selectDivisor(right, replacingMinusOne: isMinusOne), "")
    }

    /// Emits a divisor that is 1 where `isMinusOne` holds, and `right` elsewhere.
    private func selectDivisor(_ right: LLVMValueRef, replacingMinusOne isMinusOne: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildSelect(builder, isMinusOne, module.constant(1), right, "")
    }

    private func compare(_ predicate: LLVMIntPredicate, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildICmp(builder, predicate, left, right, "")
    }

    private func panic(ifZero value: LLVMValueRef, _ reason: PanicReason, at range: SourceRange) {
        panic(if: compare(LLVMIntEQ, value, module.constant(0)), reason, at: range)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private func panic(if condition: LLVMValueRef, _ reason: PanicReason, at range: SourceRange) {
        // Split on the condition into two blocks appended at the function's end.
        let panics = appendBlock(named: "panic")
        let continues = appendBlock(named: "continue")
        LLVMBuildCondBr(builder, condition, panics, continues)

        // The panic block reports the reason and the place, and never returns.
        LLVMPositionBuilderAtEnd(builder, panics)
        let message = Array("\(program.sourcePath):\(range.start): panic: \(reason.rawValue)\n".utf8)
        module.call(program.runtime.panic, [module.addConstant("rayo.panic_message", bytes: message),
                                            module.constant(Int64(message.count))])
        LLVMBuildUnreachable(builder)

        LLVMPositionBuilderAtEnd(builder, continues)
    }

    private func appendBlock(named name: String) -> LLVMBasicBlockRef {
        module.appendBlock(to: llvmFunction, named: name)
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
