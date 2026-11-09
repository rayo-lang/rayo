import RayoDiagnostics
import RayoSource
import RayoSyntax

extension BodyChecker {
    mutating func check(_ expr: Expr) -> CheckedExpr? {
        switch expr.kind {
        case .intLiteral(let digits):
            return literal(Int64(exactly: digits), in: expr.range)
        case .negativeIntLiteral(let digits):
            let value = digits == Int64.min.magnitude ? Int64.min : Int64(exactly: digits).map { -$0 }
            return literal(value, in: expr.range)
        case .boolLiteral(let value):
            return CheckedExpr(kind: .boolLiteral(value), type: .bool, range: expr.range)
        case .name(let name):
            return reference(to: name, at: expr.range)
        case .unary(let op, let operand):
            let type: RayoType = op == .negate ? .int : .bool
            return check(operand, expecting: type).map {
                CheckedExpr(kind: .unary(op, $0), type: type, range: expr.range)
            }
        case .binary(let op, let left, let right):
            let left = check(left)
            let right = check(right)
            guard let left, let right else { return nil }
            return binary(op, left, right, spelled: op.rawValue, in: expr.range)
        case .call(let name, let nameRange, let arguments):
            return call(name, at: nameRange, arguments, in: expr.range)
        case .copy(let name, let nameRange):
            return reference(to: name, at: nameRange).map {
                CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range)
            }
        }
    }

    mutating func check(_ expr: Expr, expecting type: RayoType) -> CheckedExpr? {
        guard let checked = check(expr), expect(checked, type) else { return nil }
        return checked
    }

    /// Whether `expr` has `type`, reporting it when it doesn't.
    mutating func expect(_ expr: CheckedExpr, _ type: RayoType) -> Bool {
        if expr.type == type { return true }
        errors.report(.typeMismatch(expected: "\(type)", found: "\(expr.type)"), at: expr.range)
        return false
    }

    private mutating func reference(to name: String, at range: SourceRange) -> CheckedExpr? {
        if name == "_" {
            errors.report(.underscoreValue, at: range)
            return nil
        }
        switch lookUp(name) {
        case .local(let local):
            return CheckedExpr(kind: .local(local), type: locals[local.index].type, range: range)
        case .failed:
            return nil
        case nil where declarations.function(named: name) != nil:
            errors.report(.functionAsValue(name: name), at: range)
            return nil
        case nil:
            errors.report(.notDeclared(name: name), at: range)
            return nil
        }
    }

    /// Checks `left op right`, where the source `spelled` the operator as written, such as `+=` for a
    /// compound assignment's `+`.
    mutating func binary(_ op: BinaryOperator, _ left: CheckedExpr, _ right: CheckedExpr, spelled: String,
                         in range: SourceRange) -> CheckedExpr? {
        let result: RayoType
        switch op {
        case .add, .subtract, .multiply, .divide, .remainder:
            guard operands(of: spelled, left, right, are: .int, in: range) else { return nil }
            result = .int
        case .less, .lessEqual, .greater, .greaterEqual:
            guard operands(of: spelled, left, right, are: .int, in: range) else { return nil }
            result = .bool
        case .and, .or:
            guard operands(of: spelled, left, right, are: .bool, in: range) else { return nil }
            result = .bool
        case .equal, .notEqual:
            guard left.type == right.type else {
                errors.report(.operandsDiffer(op: spelled, left: "\(left.type)", right: "\(right.type)"), at: range)
                return nil
            }
            guard left.type != .void else {
                errors.report(.voidComparison(op: spelled), at: range)
                return nil
            }
            result = .bool
        }
        return CheckedExpr(kind: .binary(op, left, right), type: result, range: range)
    }

    private mutating func operands(of spelled: String, _ left: CheckedExpr, _ right: CheckedExpr,
                                   are type: RayoType, in range: SourceRange) -> Bool {
        if left.type == type && right.type == type { return true }
        let code = ErrorCode.operandTypes(op: spelled, needs: "\(type)", left: "\(left.type)", right: "\(right.type)")
        errors.report(code, at: range)
        return false
    }

    /// Checks an integer literal, whose `value` is nil when the literal doesn't fit in an `Int`.
    private mutating func literal(_ value: Int64?, in range: SourceRange) -> CheckedExpr? {
        guard let value else {
            errors.report(.literalExceedsInt, at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: .int, range: range)
    }
}
