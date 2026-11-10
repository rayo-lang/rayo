internal import CLLVM
import RayoSource
import RayoSyntax

/// Emits the unary and binary operators on Int and Bool values into a function. Integer operations panic or wrap
/// where Rayo says they do, and so never reach LLVM's undefined cases.
struct OperatorEmitter {
    let program: ProgramEmitter
    /// The function the operators are emitted into, which a panic adds its blocks to.
    let llvmFunction: LLVMValueRef

    private var module: ModuleBuilder { program.module }
    private var builder: LLVMBuilderRef { program.module.builder }

    func unary(_ op: UnaryOperator, _ operand: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .negate: return arithmetic(.subtract, module.constant(0), operand, at: range)
        case .not: return LLVMBuildXor(builder, operand, module.constant(true), "")
        }
    }

    func binary(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: LLVMValueRef,
                at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .add: return arithmetic(.add, left, right, at: range)
        case .subtract: return arithmetic(.subtract, left, right, at: range)
        case .multiply: return arithmetic(.multiply, left, right, at: range)
        case .divide: return divide(left, right, at: range)
        case .remainder: return remainder(left, right, at: range)
        case .equal: return compare(LLVMIntEQ, left, right)
        case .notEqual: return compare(LLVMIntNE, left, right)
        case .less: return compare(LLVMIntSLT, left, right)
        case .lessEqual: return compare(LLVMIntSLE, left, right)
        case .greater: return compare(LLVMIntSGT, left, right)
        case .greaterEqual: return compare(LLVMIntSGE, left, right)
        case .and, .or: preconditionFailure("lowering turns '\(op.rawValue)' into branches")
        }
    }

    /// `left op right`: it panics on overflow where overflow is checked, and wraps where it isn't.
    private func arithmetic(_ op: OverflowingOperation, _ left: LLVMValueRef, _ right: LLVMValueRef,
                            at range: SourceRange) -> LLVMValueRef {
        // Where overflow isn't checked, it wraps.
        guard program.checksOverflow else { return wrapping(op, left, right) }
        let pair = module.call(module.intrinsic(op.intrinsicName, overloadedOn: module.int64), [left, right])
        panic(if: LLVMBuildExtractValue(builder, pair, 1, ""), "integer overflow", at: range)
        return LLVMBuildExtractValue(builder, pair, 0, "")
    }

    private func wrapping(_ op: OverflowingOperation, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        switch op {
        case .add: return LLVMBuildAdd(builder, left, right, "")
        case .subtract: return LLVMBuildSub(builder, left, right, "")
        case .multiply: return LLVMBuildMul(builder, left, right, "")
        }
    }

    private func divide(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        // Panic on a zero divisor, and, where overflow is checked, on Int.min / -1.
        panic(ifZero: right, "division by zero", at: range)
        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))
        // Where overflow is checked, the one quotient that overflows panics.
        if program.checksOverflow {
            let isMin = compare(LLVMIntEQ, left, module.constant(.min))
            panic(if: LLVMBuildAnd(builder, isMin, isMinusOne, ""), "integer overflow", at: range)
        }

        // A division by -1 negates, which wraps Int.min to itself, but LLVM leaves Int.min / -1 undefined, so
        // it divides by 1 and negates instead.
        let quotient = LLVMBuildSDiv(builder, left, divisor(right, replacingMinusOne: isMinusOne), "")
        let negated = LLVMBuildSub(builder, module.constant(0), quotient, "")
        return LLVMBuildSelect(builder, isMinusOne, negated, quotient, "")
    }

    private func remainder(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        panic(ifZero: right, "remainder by zero", at: range)

        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so it divides by 1 instead.
        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))
        return LLVMBuildSRem(builder, left, divisor(right, replacingMinusOne: isMinusOne), "")
    }

    /// `right`, or 1 where `isMinusOne` holds.
    private func divisor(_ right: LLVMValueRef, replacingMinusOne isMinusOne: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildSelect(builder, isMinusOne, module.constant(1), right, "")
    }

    private func compare(_ predicate: LLVMIntPredicate, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildICmp(builder, predicate, left, right, "")
    }

    private func panic(ifZero value: LLVMValueRef, _ reason: String, at range: SourceRange) {
        panic(if: compare(LLVMIntEQ, value, module.constant(0)), reason, at: range)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private func panic(if condition: LLVMValueRef, _ reason: String, at range: SourceRange) {
        // Branch to a block that panics when the condition holds, and to one that goes on when it doesn't.
        let panics = module.appendBlock(to: llvmFunction, named: "panic")
        let continues = module.appendBlock(to: llvmFunction, named: "continue")
        LLVMBuildCondBr(builder, condition, panics, continues)

        // The panic block reports the reason and the place, and never returns.
        LLVMPositionBuilderAtEnd(builder, panics)
        let message = Array("\(program.sourcePath):\(range.start): panic: \(reason)\n".utf8)
        module.call(program.runtime.panic, [module.addConstant("rayo.panic_message", bytes: message),
                                            module.constant(Int64(message.count))])
        LLVMBuildUnreachable(builder)

        LLVMPositionBuilderAtEnd(builder, continues)
    }
}

/// An integer operation that can overflow.
private enum OverflowingOperation: String {
    case add = "sadd"
    case subtract = "ssub"
    case multiply = "smul"

    /// The intrinsic that computes the operation and reports whether it overflowed.
    var intrinsicName: String { "llvm.\(rawValue).with.overflow" }
}
