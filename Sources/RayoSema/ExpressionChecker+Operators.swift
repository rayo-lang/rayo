import RayoDiagnostics
import RayoSource
import RayoSyntax

extension ExpressionChecker {
    /// Checks `op operandExpr`, which is untyped where its operand is.
    func unary(_ op: UnaryOperator, _ operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        switch op {
        // `-` negates an untyped operand to an untyped value, and a typed one only where it is an Int.
        case .negate:
            // An operand that failed was reported already.
            guard let operand = value(of: operandExpr) else { return nil }
            // An untyped operand gives an untyped negation.
            if case .untyped(let untyped) = operand { return .untyped(.negation(untyped, range: range)) }
            let negated = settled(operand, expecting: Expectation(.int))
            return negated.map { .typed(CheckedExpr(kind: .unary(op, $0), type: .int, range: range)) }

        // `!` takes a Bool, which no untyped value fits.
        case .not:
            let operand = check(operandExpr, expecting: Expectation(.bool))
            return operand.map { .typed(CheckedExpr(kind: .unary(op, $0), type: .bool, range: range)) }
        }
    }

    /// Checks `leftExpr op rightExpr`, which is untyped where it is arithmetic on two untyped operands.
    func binary(_ op: BinaryOperator, _ leftExpr: Expr, _ rightExpr: Expr, in range: SourceRange) -> CheckedValue? {
        // Both operands are checked, so each one's errors are reported, before the operator is.
        let left = value(of: leftExpr)
        let right = value(of: rightExpr)
        // An operand that failed was reported already.
        guard let left, let right else { return nil }

        // Arithmetic on two untyped operands gives a value of their type, so it is untyped too.
        if case .untyped(let untypedLeft) = left, case .untyped(let untypedRight) = right, op.isArithmetic {
            return .untyped(.arithmetic(op, untypedLeft, untypedRight, range: range))
        }

        // Otherwise an untyped operand takes the type of the typed one beside it, which every operator takes on both
        // sides, or its default type where it doesn't fit that type or both operands are untyped.
        let settledLeft = settled(left, toward: right.type)
        let settledRight = settled(right, toward: left.type)
        // An operand that failed was reported.
        guard let settledLeft, let settledRight else { return nil }
        return binary(op, settledLeft, settledRight, spelled: op.rawValue, in: range).map { .typed($0) }
    }

    /// Checks `left op right`, where the source `spelled` the operator as written, such as `+=` for a
    /// compound assignment's `+`.
    func binary(_ op: BinaryOperator, _ left: CheckedExpr, _ right: CheckedExpr, spelled: String,
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
                let code = ErrorCode.operandsDiffer(
                    op: spelled, left: typeName(of: left.type), right: typeName(of: right.type),
                )
                errors.report(code, at: range)
                return nil
            }
            // Comparing values of a type that doesn't compare is reported.
            guard isComparable(left.type) else {
                errors.report(.incomparable(op: spelled, type: typeName(of: left.type)), at: range)
                return nil
            }
            result = .bool
        }
        return CheckedExpr(kind: .binary(op, left, right), type: result, range: range)
    }

    /// Whether `==` and `!=` compare values of `type`.
    private func isComparable(_ type: RayoType) -> Bool {
        switch type {
        // Ints and Bools compare.
        case .int, .bool: true
        // A Void value holds nothing to compare, and a struct has no `==`.
        case .void, .structure: false
        }
    }

    /// Whether `left` and `right` both have `type`, reporting it when they don't.
    private func operands(of spelled: String, _ left: CheckedExpr, _ right: CheckedExpr,
                          are type: RayoType, in range: SourceRange) -> Bool {
        // Two operands of the type pass.
        if left.type == type && right.type == type { return true }
        let code = ErrorCode.operandTypes(
            op: spelled, needs: typeName(of: type), left: typeName(of: left.type), right: typeName(of: right.type),
        )
        errors.report(code, at: range)
        return false
    }
}

private extension BinaryOperator {
    /// Whether the operator gives a value of its operands' type.
    var isArithmetic: Bool {
        switch self {
        case .add, .subtract, .multiply, .divide, .remainder: true
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual, .and, .or: false
        }
    }
}
