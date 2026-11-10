import RayoSema
import RayoSource

/// Lowers expressions into the current block of a function's control-flow graph, as the operations that compute
/// them and the operands that hold their values.
struct ExpressionLowering {
    let builder: FunctionBuilder

    func rvalue(of expr: CheckedExpr) -> Rvalue {
        switch expr.kind {
        // A constant or a local is an operand as it is, and so is `&&` or `||`, which lowers to branches.
        case .intLiteral, .boolLiteral, .local, .move, .binary(.and, _, _), .binary(.or, _, _):
            return .use(operand(of: expr))
        case .unary(let op, let operand): return .unary(op, self.operand(of: operand))
        case .binary(let op, let left, let right): return .binary(op, operand(of: left), operand(of: right))
        case .call(let callee, let arguments): return .call(callee, arguments: arguments.map { operand(of: $0) })
        }
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary unless it is a constant
    /// or a local.
    func operand(of expr: CheckedExpr) -> Operand {
        switch expr.kind {
        case .intLiteral(let value): return .constant(.int(value))
        case .boolLiteral(let value): return .constant(.bool(value))
        case .local(let local): return .read(Place(local: local, range: expr.range))
        case .move(let local): return .move(Place(local: local, range: expr.range))
        // `&&` evaluates its right operand only when its left one is true,
        case .binary(.and, let left, let right):
            return shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range)
        // and `||` only when its left one is false.
        case .binary(.or, let left, let right):
            return shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range)
        // Any other expression is computed into a temporary.
        default: return lowerIntoTemporary(expr)
        }
    }

    /// Computes `expr` into a new temporary, and returns an operand that reads it.
    private func lowerIntoTemporary(_ expr: CheckedExpr) -> Operand {
        let temporary = builder.newTemporary(expr.type, at: expr.range)
        builder.emit(rvalue(of: expr), into: temporary, range: expr.range)
        return .read(temporary)
    }

    /// Lowers `left && right` or `left || right` into branches, and returns an operand that holds the result: `left`
    /// when `left` is `decidingValue`, and otherwise `right`, which is evaluated only then.
    private func shortCircuit(_ left: CheckedExpr, _ right: CheckedExpr, decidedWhenLeftIs decidingValue: Bool,
                              range: SourceRange) -> Operand {
        // The result starts as `left`'s value, which is the result when it is `decidingValue`.
        let result = builder.newTemporary(.bool, at: range)
        let resultValue = Operand.read(result)
        builder.emit(.use(operand(of: left)), into: result, range: range)

        // `right` is evaluated in a block of its own, which only a `left` that doesn't decide reaches.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)
        builder.emit(.use(operand(of: right)), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}
