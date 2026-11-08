import RayoSyntax

/// Integer operations, which panic or wrap where Rayo says they do, and so never reach LLVM's undefined cases.
extension FunctionWriter {
    /// `left op right`, for `op` one of LLVM's `add`, `sub` and `mul`: it panics on overflow where overflow is
    /// checked, and wraps where it isn't.
    mutating func arithmetic(_ op: String, _ left: String, _ right: String, at range: SourceRange) -> String {
        let result = newValue()
        guard checksOverflow else {
            emit("\(result) = \(op) i64 \(left), \(right)")
            return result
        }
        let pair = newValue()
        emit("\(pair) = call { i64, i1 } @llvm.s\(op).with.overflow.i64(i64 \(left), i64 \(right))")
        let overflowed = newValue()
        emit("\(overflowed) = extractvalue { i64, i1 } \(pair), 1")
        panic(if: overflowed, "integer overflow", at: range)
        emit("\(result) = extractvalue { i64, i1 } \(pair), 0")
        return result
    }

    mutating func divide(_ left: String, _ right: String, at range: SourceRange) -> String {
        panic(ifZero: right, "division by zero", at: range)
        let isMinusOne = newValue()
        emit("\(isMinusOne) = icmp eq i64 \(right), -1")
        if checksOverflow {
            let isMin = newValue()
            emit("\(isMin) = icmp eq i64 \(left), \(Int64.min)")
            let overflows = newValue()
            emit("\(overflows) = and i1 \(isMin), \(isMinusOne)")
            panic(if: overflows, "integer overflow", at: range)
        }
        // A division by -1 negates, which wraps Int.min to itself, but LLVM leaves Int.min / -1 undefined, so
        // it divides by 1 and negates instead.
        let quotient = newValue()
        emit("\(quotient) = sdiv i64 \(left), \(divisor(right, replacingMinusOne: isMinusOne))")
        let negated = newValue()
        emit("\(negated) = sub i64 0, \(quotient)")
        let result = newValue()
        emit("\(result) = select i1 \(isMinusOne), i64 \(negated), i64 \(quotient)")
        return result
    }

    mutating func remainder(_ left: String, _ right: String, at range: SourceRange) -> String {
        panic(ifZero: right, "remainder by zero", at: range)
        // Every remainder by -1 is 0, but LLVM leaves Int.min % -1 undefined, so it divides by 1 instead.
        let isMinusOne = newValue()
        emit("\(isMinusOne) = icmp eq i64 \(right), -1")
        let result = newValue()
        emit("\(result) = srem i64 \(left), \(divisor(right, replacingMinusOne: isMinusOne))")
        return result
    }

    /// `right`, or 1 where `isMinusOne` holds.
    private mutating func divisor(_ right: String, replacingMinusOne isMinusOne: String) -> String {
        let divisor = newValue()
        emit("\(divisor) = select i1 \(isMinusOne), i64 1, i64 \(right)")
        return divisor
    }

    private mutating func panic(ifZero value: String, _ reason: String, at range: SourceRange) {
        let isZero = newValue()
        emit("\(isZero) = icmp eq i64 \(value), 0")
        panic(if: isZero, reason, at: range)
    }

    /// Branches to a panic for `reason` when `condition` holds, and continues in a new block otherwise.
    private mutating func panic(if condition: String, _ reason: String, at range: SourceRange) {
        let message = module.panicMessage(reason, at: range)
        let panics = newLabel()
        let continues = newLabel()
        emit("br i1 \(condition), label %\(panics), label %\(continues)")
        lines.append("\(panics):")
        emit("call void @rayo.panic(ptr \(message.name), i64 \(message.length))")
        emit("unreachable")
        lines.append("\(continues):")
    }
}
