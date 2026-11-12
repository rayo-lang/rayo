import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks expressions: the names they use, their operators' operands, and the types they give.
struct ExpressionChecker {
    let file: FileChecker
    let names: NameScopes

    private var errors: ErrorList { file.errors }

    /// The name an error gives `type`.
    func typeName(of type: RayoType) -> TypeName {
        file.declarations.typeName(of: type)
    }

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
            // A value that failed was reported already.
            guard let value = check(base) else { return nil }
            return field(named: name, at: nameRange, of: value, in: expr.range)?.read

        // A `copy` reads the place and leaves its value in it, and it covers the whole `copy place`.
        case .copy(let place):
            return check(place).map { CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range) }
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
        errors.report(.typeMismatch(expected: typeName(of: type), found: typeName(of: expr.type)), at: expr.range)
        return false
    }

    /// Checks `expr` as the value a declaration, an assignment, a `return`, `_ =` or a struct's initializer takes,
    /// which moves a local's value out of it.
    func checkTaken(_ expr: Expr) -> CheckedExpr? {
        // An expression that failed was reported already.
        guard let value = check(expr) else { return nil }

        // A `copy` checks to a read of the place it copies, so only a place written bare is moved.
        return switch (expr.kind, value.kind) {
        // A local written bare is moved.
        case (.name(let name), .local(let local)): move(local, named: name, readBy: value)
        // A field written bare is moved out of the struct that holds it.
        case (.member, _): moveField(readBy: value)
        // Any other value, a copy included, is a new one, which is taken as it is.
        default: value
        }
    }

    /// Turns `value`, which reads `local`, into a move of its value, reporting it when `local` is a borrowed
    /// parameter.
    private func move(_ local: LocalID, named name: String, readBy value: CheckedExpr) -> CheckedExpr? {
        // A borrowed parameter can't be moved from, since its caller still owns the value.
        guard names[local].kind != .parameter else {
            errors.report(.moveFromParameter(name: name), at: value.range)
            return nil
        }
        return CheckedExpr(kind: .move(value), type: value.type, range: value.range)
    }

    /// Turns `value`, which reads a field, into a move of the field out of the struct that holds it, reporting it
    /// when a borrowed parameter holds the struct.
    private func moveField(readBy value: CheckedExpr) -> CheckedExpr? {
        // A borrowed parameter's field can't be moved out, since its caller still owns the whole value.
        if let path = parameterPath(to: value) {
            errors.report(.moveFieldFromParameter(field: path.spelling, parameter: path.parameter), at: value.range)
            return nil
        }
        return CheckedExpr(kind: .move(value), type: value.type, range: value.range)
    }

    /// The borrowed parameter that `place`, a local or a field read through one, lies in, and the place as the source
    /// names it, such as `e.stats.hp`; or nil where the place lies in a `let`, a `var` or a temporary.
    private func parameterPath(to place: CheckedExpr) -> (parameter: String, spelling: String)? {
        switch place.kind {
        // A field lies in whatever holds its struct, and takes its name from that struct's declaration.
        case .field(let structure, let index):
            // A struct that lies in no parameter holds its fields there too.
            guard let holder = parameterPath(to: structure), case .structure(let id) = structure.type else {
                return nil
            }
            return (holder.parameter, holder.spelling + "." + file.declarations.fields(of: id)[index].name)

        // A local is the place's own, which may be a borrowed parameter.
        case .local(let local):
            return names[local].kind == .parameter ? (names[local].name, names[local].name) : nil

        // Any other value is a temporary, which no parameter holds.
        default:
            return nil
        }
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

    /// Checks `value.name`, where the source writes `name` at `nameRange`, as a read of the field `name` of the struct
    /// value `value`, which keeps the field. Returns the read, and whether the field is a `var` or a `let`.
    func field(named name: String, at nameRange: SourceRange, of value: CheckedExpr,
               in range: SourceRange) -> (read: CheckedExpr, kind: BindingKind)? {
        // Find the field among the struct's; a value of any other type has none.
        let fields: [DeclaredField] =
            if case .structure(let id) = value.type { file.declarations.fields(of: id) } else { [] }
        // A name that names no field of the value's type is reported.
        guard let index = fields.firstIndex(where: { $0.name == name }) else {
            errors.report(.noSuchField(type: typeName(of: value.type), field: name), at: nameRange)
            return nil
        }

        // A field whose declaration failed was reported there.
        guard let type = fields[index].type else { return nil }
        return (CheckedExpr(kind: .field(value, index: index), type: type, range: range), fields[index].kind)
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

    /// Checks an integer literal, whose `value` is nil when the literal doesn't fit in an `Int`.
    private func literal(_ value: Int64?, in range: SourceRange) -> CheckedExpr? {
        // A literal that doesn't fit is reported.
        guard let value else {
            errors.report(.literalExceedsInt(type: typeName(of: .int)), at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: .int, range: range)
    }
}
