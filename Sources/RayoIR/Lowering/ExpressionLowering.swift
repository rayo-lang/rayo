import RayoSema
import RayoSource

/// Lowers expressions into the current block of the function a builder builds, as the operations that compute them
/// and the operands that hold their values.
enum ExpressionLowering {
    /// Lowers `expr` into `builder`, as the computation of its value into `destination`, or, where `destination` is
    /// nil, of a value that is dropped.
    static func compute(_ expr: CheckedExpr, into destination: Place?, in builder: inout FunctionBuilder) {
        let value = rvalue(of: expr, in: &builder)
        builder.emit(value, into: destination, range: expr.range)
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary of `builder` unless it is
    /// a constant or a local.
    static func operand(of expr: CheckedExpr, in builder: inout FunctionBuilder) -> Operand {
        switch expr.kind {
        // An integer is a constant operand.
        case .intLiteral(let value): .constant(.int(value))
        // So is a Bool.
        case .boolLiteral(let value): .constant(.bool(value))
        // A local that the checker reads is read, keeping its value.
        case .local(let local): .read(Place(local: local, range: expr.range))
        // A local that the checker moves gives its value up.
        case .move(let local): .move(Place(local: local, range: expr.range))
        // `&&` evaluates its right operand only when its left one is true.
        case .binary(.and, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range, in: &builder)
        // `||` evaluates its right operand only when its left one is false.
        case .binary(.or, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range, in: &builder)
        // Any other operation, and a call, is computed into a temporary.
        case .unary, .binary, .call:
            lowerIntoTemporary(expr, in: &builder)
        }
    }

    /// Lowers `expr` to the operation that computes its value, computing its operands into `builder` first.
    private static func rvalue(of expr: CheckedExpr, in builder: inout FunctionBuilder) -> Rvalue {
        switch expr.kind {
        // A constant or a local is an operand as it is, and so is `&&` or `||`, which lowers to branches.
        case .intLiteral, .boolLiteral, .local, .move, .binary(.and, _, _), .binary(.or, _, _):
            .use(operand(of: expr, in: &builder))
        // A unary operation applies to its operand, computed first.
        case .unary(let op, let value):
            .unary(op, operand(of: value, in: &builder))
        // The left operand is computed before the right one, in the order the source reads.
        case .binary(let op, let left, let right):
            .binary(op, operand(of: left, in: &builder), operand(of: right, in: &builder))
        // So are the arguments of a call, from first to last.
        case .call(let callee, let arguments):
            .call(callee, arguments: arguments.map { operand(of: $0, in: &builder) })
        }
    }

    /// Computes `expr` into a new temporary of `builder`, and returns an operand that reads it.
    private static func lowerIntoTemporary(_ expr: CheckedExpr, in builder: inout FunctionBuilder) -> Operand {
        let temporary = builder.newTemporary(expr.type, at: expr.range)
        compute(expr, into: temporary, in: &builder)
        return .read(temporary)
    }

    /// Lowers `left && right` or `left || right` into branches, and returns an operand that holds the result: `left`
    /// when `left` is `decidingValue`, and otherwise `right`, which is evaluated only then.
    private static func shortCircuit(
        _ left: CheckedExpr, _ right: CheckedExpr, decidedWhenLeftIs decidingValue: Bool, range: SourceRange,
        in builder: inout FunctionBuilder,
    ) -> Operand {
        // The result starts as `left`'s value, which is the result when it is `decidingValue`.
        let result = builder.newTemporary(.bool, at: range)
        let resultValue = Operand.read(result)
        let leftValue = operand(of: left, in: &builder)
        builder.emit(.use(leftValue), into: result, range: range)

        // A `left` that decides goes on to the join, and any other to a block of its own that evaluates `right`.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)

        // There `right`'s value becomes the result, and both paths meet at the join, where lowering goes on.
        let rightValue = operand(of: right, in: &builder)
        builder.emit(.use(rightValue), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}
