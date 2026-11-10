import RayoDiagnostics
import RayoSource
import RayoSyntax

extension BodyChecker {
    mutating func check(_ expr: Expr) -> CheckedExpr? {
        switch expr.kind {
        // An integer literal is an Int, if it fits in one.
        case .intLiteral(let digits):
            return literal(Int64(exactly: digits), in: expr.range)

        // A negative literal fits one value more than a positive one: `Int.min`, whose magnitude no Int holds.
        case .negativeIntLiteral(let digits):
            let value = digits == Int64.min.magnitude ? Int64.min : Int64(exactly: digits).map { -$0 }
            return literal(value, in: expr.range)

        // `true` and `false` are Bools.
        case .boolLiteral(let value):
            return CheckedExpr(kind: .boolLiteral(value), type: .bool, range: expr.range)

        // A name reads the local it names.
        case .name(let name):
            return reference(to: name, at: expr.range)

        // `-` negates an Int, and `!` a Bool.
        case .unary(let op, let operand):
            let type: RayoType = op == .negate ? .int : .bool
            return check(operand, expecting: type).map {
                CheckedExpr(kind: .unary(op, $0), type: type, range: expr.range)
            }

        // Both operands are checked, so each one's errors are reported, before the operator is.
        case .binary(let op, let left, let right):
            let left = check(left)
            let right = check(right)
            // An operand that failed was reported already.
            guard let left, let right else { return nil }
            return binary(op, left, right, spelled: op.rawValue, in: expr.range)

        // A call reaches one of the functions its name names.
        case .call(let name, let nameRange, let arguments):
            return call(name, at: nameRange, arguments, in: expr.range)

        // A `copy` reads the local and leaves its value in it, and it covers the whole `copy name`.
        case .copy(let name, let nameRange):
            return reference(to: name, at: nameRange).map {
                CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range)
            }
        }
    }

    mutating func check(_ expr: Expr, expecting type: RayoType) -> CheckedExpr? {
        // An expression that failed, or that has another type, was reported.
        guard let checked = check(expr), expect(checked, type) else { return nil }
        return checked
    }

    /// Whether `expr` has `type`, reporting it when it doesn't.
    mutating func expect(_ expr: CheckedExpr, _ type: RayoType) -> Bool {
        // A value of the type passes.
        if expr.type == type { return true }
        errors.report(.typeMismatch(expected: "\(type)", found: "\(expr.type)"), at: expr.range)
        return false
    }

    private mutating func reference(to name: String, at range: SourceRange) -> CheckedExpr? {
        // `_` names no value; it only drops one, or leaves a parameter unnamed.
        if name == "_" {
            errors.report(.underscoreValue, at: range)
            return nil
        }
        switch lookUp(name, for: .ordinary) {
        // A local reads its value.
        case .inScope(.local(let local)):
            return CheckedExpr(kind: .local(local), type: locals[local.index].type, range: range)

        // A local whose declaration failed was reported there.
        case .inScope(.failed):
            return nil

        // A function is no value.
        case .functions:
            errors.report(.functionAsValue(name: name), at: range)
            return nil

        // Nothing has the name.
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
        // Arithmetic takes two Ints, and gives an Int.
        case .add, .subtract, .multiply, .divide, .remainder:
            // Operands of another type were reported.
            guard operands(of: spelled, left, right, are: .int, in: range) else { return nil }
            result = .int

        // An ordering takes two Ints, and gives a Bool.
        case .less, .lessEqual, .greater, .greaterEqual:
            // Operands of another type were reported.
            guard operands(of: spelled, left, right, are: .int, in: range) else { return nil }
            result = .bool

        // `&&` and `||` take two Bools, and give a Bool.
        case .and, .or:
            // Operands of another type were reported.
            guard operands(of: spelled, left, right, are: .bool, in: range) else { return nil }
            result = .bool

        // `==` and `!=` take two values of one type, and give a Bool.
        case .equal, .notEqual:
            // Comparing values of two types is reported.
            guard left.type == right.type else {
                errors.report(.operandsDiffer(op: spelled, left: "\(left.type)", right: "\(right.type)"), at: range)
                return nil
            }
            // Void values have nothing to compare.
            guard left.type != .void else {
                errors.report(.voidComparison(op: spelled), at: range)
                return nil
            }
            result = .bool
        }
        return CheckedExpr(kind: .binary(op, left, right), type: result, range: range)
    }

    /// Whether `left` and `right` both have `type`, reporting it when they don't.
    private mutating func operands(of spelled: String, _ left: CheckedExpr, _ right: CheckedExpr,
                                   are type: RayoType, in range: SourceRange) -> Bool {
        // Two operands of the type pass.
        if left.type == type && right.type == type { return true }
        let code = ErrorCode.operandTypes(op: spelled, needs: "\(type)", left: "\(left.type)", right: "\(right.type)")
        errors.report(code, at: range)
        return false
    }

    /// Checks an integer literal, whose `value` is nil when the literal doesn't fit in an `Int`.
    private mutating func literal(_ value: Int64?, in range: SourceRange) -> CheckedExpr? {
        // A literal that doesn't fit is reported.
        guard let value else {
            errors.report(.literalExceedsInt, at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: .int, range: range)
    }
}
