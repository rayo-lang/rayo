internal import CLLVM
import RayoSource

/// An integer operation that can overflow.
enum OverflowingOperation: String {
    case add = "sadd"
    case subtract = "ssub"
    case multiply = "smul"

    /// The intrinsic that computes the operation and reports whether it overflowed.
    var intrinsicName: String { "llvm.\(rawValue).with.overflow" }
}

/// Integer operations, which panic or wrap where Rayo says they do, and so never reach LLVM's undefined cases.
extension FunctionEmitter {
    /// `left op right`: it panics on overflow where overflow is checked, and wraps where it isn't.
    func arithmetic(_ op: OverflowingOperation, _ left: LLVMValueRef, _ right: LLVMValueRef,
                    at range: SourceRange) -> LLVMValueRef {
        guard checksOverflow else { return wrapping(op, left, right) }
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

    func divide(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        panic(ifZero: right, "division by zero", at: range)
        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))
        if checksOverflow {
            let isMin = compare(LLVMIntEQ, left, module.constant(.min))
            panic(if: LLVMBuildAnd(builder, isMin, isMinusOne, ""), "integer overflow", at: range)
        }
        // A division by -1 negates, which wraps Int.min to itself, but LLVM leaves Int.min / -1 undefined, so
        // it divides by 1 and negates instead.
        let quotient = LLVMBuildSDiv(builder, left, divisor(right, replacingMinusOne: isMinusOne), "")
        let negated = LLVMBuildSub(builder, module.constant(0), quotient, "")
        return LLVMBuildSelect(builder, isMinusOne, negated, quotient, "")
    }

    func remainder(_ left: LLVMValueRef, _ right: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        panic(ifZero: right, "remainder by zero", at: range)
        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so it divides by 1 instead.
        let isMinusOne = compare(LLVMIntEQ, right, module.constant(-1))
        return LLVMBuildSRem(builder, left, divisor(right, replacingMinusOne: isMinusOne), "")
    }

    /// `right`, or 1 where `isMinusOne` holds.
    private func divisor(_ right: LLVMValueRef, replacingMinusOne isMinusOne: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildSelect(builder, isMinusOne, module.constant(1), right, "")
    }

    private func panic(ifZero value: LLVMValueRef, _ reason: String, at range: SourceRange) {
        panic(if: compare(LLVMIntEQ, value, module.constant(0)), reason, at: range)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private func panic(if condition: LLVMValueRef, _ reason: String, at range: SourceRange) {
        let message = Array("\(program.sourcePath):\(range.start): panic: \(reason)\n".utf8)
        let panics = appendBlock(named: "panic")
        let continues = appendBlock(named: "continue")
        LLVMBuildCondBr(builder, condition, panics, continues)
        LLVMPositionBuilderAtEnd(builder, panics)
        module.call(program.runtime.panic, [module.addConstant("rayo.panic_message", bytes: message),
                                            module.constant(Int64(message.count))])
        LLVMBuildUnreachable(builder)
        LLVMPositionBuilderAtEnd(builder, continues)
    }
}
