import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks expressions: the names they use, their operators' operands, and the types they give.
struct ExpressionChecker {
    let file: FileChecker
    let names: NameScopes

    private var errors: ErrorList { file.errors }

    func check(_ expr: Expr) -> CheckedExpr? {
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

        // A call reaches one of the functions its name names, or the initializer of the struct it names.
        case .call(let name, let nameRange, let arguments):
            return CallChecker(expressions: self).call(name, at: nameRange, arguments, in: expr.range)

        // A member of a struct value is one of its fields.
        case .member(let base, let name, let nameRange):
            return field(named: name, at: nameRange, of: base, in: expr.range)

        // A `copy` reads the local and leaves its value in it, and it covers the whole `copy name`.
        case .copy(let name, let nameRange):
            return reference(to: name, at: nameRange).map {
                CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range)
            }
        }
    }

    func check(_ expr: Expr, expecting type: RayoType) -> CheckedExpr? {
        // An expression that failed, or that has another type, was reported.
        guard let checked = check(expr), expect(checked, type) else { return nil }
        return checked
    }

    /// Whether `expr` has `type`, reporting it when it doesn't.
    func expect(_ expr: CheckedExpr, _ type: RayoType) -> Bool {
        // A value of the type passes.
        if expr.type == type { return true }
        errors.report(.typeMismatch(expected: "\(type)", found: "\(expr.type)"), at: expr.range)
        return false
    }

    /// Checks `expr` as the value a declaration, an assignment, a `return`, `_ =` or a struct's initializer takes,
    /// which moves a local's value out of it.
    func checkTaken(_ expr: Expr) -> CheckedExpr? {
        // An expression that failed was reported already.
        guard let value = check(expr) else { return nil }
        // Taking a field would move it out of its struct, which rayoc doesn't support.
        if case .field = value.kind {
            errors.report(.fieldMove, at: value.range)
            return nil
        }
        // A `copy` of a local checks to a read of it too, so only a bare name moves.
        guard case .name(let name) = expr.kind, case .local(let local) = value.kind else { return value }
        return move(local, named: name, readBy: value)
    }

    /// Turns `value`, which reads `local`, into a move of its value, reporting it when `local` is a borrowed
    /// parameter.
    private func move(_ local: LocalID, named name: String, readBy value: CheckedExpr) -> CheckedExpr? {
        // A borrowed parameter can't be moved from, since its caller still owns the value.
        guard names[local].kind != .parameter else {
            errors.report(.moveFromParameter(name: name), at: value.range)
            return nil
        }
        return CheckedExpr(kind: .move(local), type: value.type, range: value.range)
    }

    private func reference(to name: String, at range: SourceRange) -> CheckedExpr? {
        // `_` names no value; it only drops one, or leaves a parameter unnamed.
        if name == "_" {
            errors.report(.underscoreValue, at: range)
            return nil
        }
        switch names.lookUp(name, for: .ordinary) {
        // A local reads its value.
        case .inScope(.local(let local)):
            return CheckedExpr(kind: .local(local), type: names[local].type, range: range)

        // A local whose declaration failed was reported there.
        case .inScope(.failed):
            return nil

        // A function is no value.
        case .functions:
            errors.report(.functionAsValue(name: name), at: range)
            return nil

        // A struct's name is a type, which is no value.
        case .structure:
            errors.report(.typeAsValue(name: name), at: range)
            return nil

        // Nothing has the name.
        case nil:
            errors.report(.notDeclared(name: name), at: range)
            return nil
        }
    }

    /// Checks `base.name`, where the source writes `name` at `nameRange`, as a read of the field `name` of the struct
    /// value `base`, which keeps the field.
    private func field(named name: String, at nameRange: SourceRange, of base: Expr,
                       in range: SourceRange) -> CheckedExpr? {
        // A value that failed was reported already.
        guard let value = check(base) else { return nil }

        // Find the field among the struct's; a value of any other type has none.
        let fields: [DeclaredField] =
            if case .structure(let id) = value.type { file.declarations.fields(of: id) } else { [] }
        // A name that names no field of the value's type is reported.
        guard let index = fields.firstIndex(where: { $0.name == name }) else {
            errors.report(.noSuchField(type: "\(value.type)", field: name), at: nameRange)
            return nil
        }

        // A field whose declaration failed was reported there.
        guard let type = fields[index].type else { return nil }
        return CheckedExpr(kind: .field(value, index: index), type: type, range: range)
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
                errors.report(.operandsDiffer(op: spelled, left: "\(left.type)", right: "\(right.type)"), at: range)
                return nil
            }
            // Comparing values of a type that doesn't compare is reported.
            guard isComparable(left.type) else {
                errors.report(.incomparable(op: spelled, type: "\(left.type)"), at: range)
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
        let code = ErrorCode.operandTypes(op: spelled, needs: "\(type)", left: "\(left.type)", right: "\(right.type)")
        errors.report(code, at: range)
        return false
    }

    /// Checks an integer literal, whose `value` is nil when the literal doesn't fit in an `Int`.
    private func literal(_ value: Int64?, in range: SourceRange) -> CheckedExpr? {
        // A literal that doesn't fit is reported.
        guard let value else {
            errors.report(.literalExceedsInt, at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: .int, range: range)
    }
}
