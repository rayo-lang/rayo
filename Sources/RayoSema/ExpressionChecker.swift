import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks expressions: the names they use, their operators' operands, and the types they give.
struct ExpressionChecker {
    let file: FileChecker
    let names: NameScopes
    /// Where a `return`, a `break` and a `continue` in the code being checked leave for.
    let jumps: JumpTargets

    private var errors: ErrorList { file.errors }

    /// A checker of the expressions in the body of a loop that the code being checked holds.
    var insideLoop: ExpressionChecker {
        ExpressionChecker(file: file, names: names, jumps: jumps.insideLoop)
    }

    /// The name an error gives `type`.
    func typeName(of type: RayoType) -> TypeName {
        file.declarations.typeName(of: type)
    }

    /// Checks `expr` as the value of a position that `use`s it, and that expects `expected` of it where it expects a
    /// type. An untyped value takes the expected type where it fits it, and its default type where it doesn't.
    func check(_ expr: Expr, as use: ValueUse = .read, expecting expected: Expectation? = nil) -> CheckedExpr? {
        // An `if` hands its position to the branch that runs, so each branch's value is checked as the position's.
        if case .if(let ifExpr) = expr.kind {
            return IfChecker(expressions: self).check(ifExpr, in: expr.range, as: use, expecting: expected)
        }

        // Any other value is checked on its own, settled toward the type the position expects, and used as the
        // position uses it.
        // A value that failed was reported.
        guard let value = value(of: expr) else { return nil }
        // So was a literal that the type it settles to can't hold.
        guard let settled = settled(value, toward: expected?.type) else { return nil }
        let used = switch use {
        case .read: settled
        case .take: taken(settled, writtenAs: expr)
        }

        // A value passes where the position expects no type.
        guard let expected else { return used }
        return expect(used.type, at: used.range, expected) ? used : nil
    }

    /// Checks `expr` on its own, leaving it untyped where it is a literal, or a negation or arithmetic on untyped
    /// values.
    func value(of expr: Expr) -> CheckedValue? {
        switch expr.kind {
        // An integer literal is untyped until its position settles it.
        case .intLiteral(let digits):
            .untyped(.integer(magnitude: digits, isNegative: false, range: expr.range))

        // So is a negative one, which keeps its sign until the type that holds it is known.
        case .negativeIntLiteral(let digits):
            .untyped(.integer(magnitude: digits, isNegative: true, range: expr.range))

        // `-` is untyped where its operand is, and `!` is a Bool.
        case .unary(let op, let operand):
            unary(op, operand, in: expr.range)

        // A binary operator is untyped where it is arithmetic and both its operands are.
        case .binary(let op, let left, let right):
            binary(op, left, right, in: expr.range)

        // `true` and `false` are Bools.
        case .boolLiteral(let value):
            .typed(CheckedExpr(kind: .boolLiteral(value), type: .bool, range: expr.range))

        // A name reads the local it names, and a member a field of the place its base names.
        case .name, .member:
            place(expr, under: self).map {
                .typed(CheckedExpr(kind: .place($0.place), type: $0.type, range: expr.range))
            }

        // A call reaches one of the functions its callee names, or makes the struct it names.
        case .call(let callee, let arguments):
            CallChecker(expressions: self).call(callee, arguments, in: expr.range).map { .typed($0) }

        // An implicit member names a member of the type its position expects, which no position gives yet.
        case .implicitMember:
            unsupportedImplicitMember(at: expr.range)

        // A `copy` reads the place and leaves its value in it, and it covers the whole `copy place`.
        case .copy(let place):
            check(place).map { .typed(CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range)) }

        // An `if` read for its value gives the value of the branch that runs.
        case .if:
            check(expr).map { .typed($0) }
        }
    }

    /// Settles `value` to `type` where it is untyped and fits `type`, and to its default type where it is untyped
    /// otherwise. A typed value is given back as it is.
    func settled(_ value: CheckedValue, toward type: RayoType?) -> CheckedExpr? {
        switch value {
        case .typed(let typed): typed
        case .untyped(let untyped): settled(untyped, toward: type)
        }
    }

    /// Settles each of `values` that checked to its default type where it is untyped, so the literals in it that
    /// their default type can't hold are reported, where the expression that holds them fails for another reason.
    func reportSettlingErrors(of values: [CheckedValue?]) {
        for case .untyped(let untyped)? in values {
            _ = settled(untyped, toward: nil)
        }
    }

    /// Settles `value` toward the type `expected` names, and checks it against that type.
    func settled(_ value: CheckedValue, expecting expected: Expectation) -> CheckedExpr? {
        // A value that failed was reported.
        guard let settled = settled(value, toward: expected.type) else { return nil }
        return expect(settled.type, at: settled.range, expected) ? settled : nil
    }

    /// Whether a value of `type`, which the source gives at `range`, has the type `expected` names, reporting its
    /// mismatch when it doesn't.
    func expect(_ type: RayoType, at range: SourceRange, _ expected: Expectation) -> Bool {
        // A value of the type passes.
        if type == expected.type { return true }
        errors.report(expected.mismatch(typeName(of: expected.type), typeName(of: type)), at: range)
        return false
    }

    /// Settles `untyped` to `type` where it fits it, and to its default type where it doesn't or `type` is nil.
    private func settled(_ untyped: UntypedValue, toward type: RayoType?) -> CheckedExpr? {
        let settledType = if let type, untyped.fits(type) { type } else { untyped.defaultType }
        return untyped.settled(to: settledType, named: typeName(of: settledType), reporting: errors)
    }

    /// Reports the implicit member at `range`, which isn't supported, and returns nil.
    private func unsupportedImplicitMember(at range: SourceRange) -> CheckedValue? {
        errors.report(.unsupportedImplicitMember, at: range)
        return nil
    }

    /// Checks `op operandExpr`, which is untyped where `op` is `-` and its operand is untyped.
    private func unary(_ op: UnaryOperator, _ operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        switch op {
        case .negate: negation(of: operandExpr, in: range)
        case .not: not(operandExpr, in: range)
        }
    }

    /// Checks `-operandExpr`, which negates an untyped operand to an untyped value, and a typed one only where it is
    /// an Int.
    private func negation(of operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        // An operand that failed was reported already.
        guard let operand = value(of: operandExpr) else { return nil }
        // An untyped operand gives an untyped negation.
        if case .untyped(let untyped) = operand { return .untyped(.negation(untyped, range: range)) }
        let negated = settled(operand, expecting: Expectation(.int))
        return negated.map { .typed(CheckedExpr(kind: .unary(.negate, $0), type: .int, range: range)) }
    }

    /// Checks `!operandExpr`, which takes a Bool, a type no untyped value fits.
    private func not(_ operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        let operand = check(operandExpr, expecting: Expectation(.bool))
        return operand.map { .typed(CheckedExpr(kind: .unary(.not, $0), type: .bool, range: range)) }
    }

    /// Checks `leftExpr op rightExpr`, which is untyped where it is arithmetic on two untyped operands.
    private func binary(_ op: BinaryOperator, _ leftExpr: Expr, _ rightExpr: Expr,
                        in range: SourceRange) -> CheckedValue? {
        // Both operands are checked, so each one's errors are reported, before the operator is.
        let left = value(of: leftExpr)
        let right = value(of: rightExpr)
        // An operand that failed was reported already, and the other one's literals are settled for their own errors.
        guard let left, let right else {
            reportSettlingErrors(of: [left, right])
            return nil
        }

        // The operator is checked as what it means, and an error names it as the source spells it.
        let checkedOp = CheckedBinaryOperator(op)

        // Arithmetic on two untyped operands gives a value of their type, so it is untyped too.
        if case .untyped(let untypedLeft) = left, case .untyped(let untypedRight) = right, checkedOp.isArithmetic {
            return .untyped(.arithmetic(checkedOp, untypedLeft, untypedRight, range: range))
        }

        // Otherwise an untyped operand takes the type of the typed one beside it, which every operator takes on both
        // sides, or its default type where it doesn't fit that type or both operands are untyped.
        let settledLeft = settled(left, toward: right.type)
        let settledRight = settled(right, toward: left.type)
        // An operand that failed was reported.
        guard let settledLeft, let settledRight else { return nil }
        return binary(checkedOp, settledLeft, settledRight, spelled: op.rawValue, in: range).map { .typed($0) }
    }

    /// Turns `value`, which `expr` gives, into the value its position takes, which moves a place's value out of it.
    private func taken(_ value: CheckedExpr, writtenAs expr: Expr) -> CheckedExpr {
        // A `copy` checks to a read of the place it copies, so only a place written bare is moved.
        switch (expr.kind, value.kind) {
        // A local, or a field, written bare is moved.
        case (.name, .place(let place)), (.member, .place(let place)):
            CheckedExpr(kind: .move(place), type: value.type, range: value.range)
        // Any other value, a copy included, is a new one, which is taken as it is.
        default: value
        }
    }

    /// Checks `expr` as a place that `rules` admit: a root they check, then each field the source steps into from it.
    /// Returns nil where the root or a field fails, which was reported.
    func place(_ expr: Expr, under rules: some PlaceRules) -> TypedPlace? {
        place(expr, under: rules, holdsFields: false)
    }

    /// Checks `expr` as a place that `rules` admit, which holds the fields the source steps into when `holdsFields`
    /// is true.
    private func place(_ expr: Expr, under rules: some PlaceRules, holdsFields: Bool) -> TypedPlace? {
        // Anything but a member is the place's root.
        guard case .member(let base, let name, let nameRange) = expr.kind else {
            return rules.root(expr, holdsFields: holdsFields)
        }

        // A member steps into a field of the place its base names; a base that failed was reported.
        guard let holder = place(base, under: rules, holdsFields: true) else { return nil }
        // So was a field that the holder doesn't have, or that the rules don't admit.
        guard let (index, field, type) = field(named: name, at: nameRange, of: holder.type),
              rules.admits(field, at: nameRange)
        else { return nil }
        return (holder.place.appending(.field(index, range: expr.range)), type)
    }

    /// The field called `name` of a value of `type`, which the source names at `nameRange`: its place in its struct's
    /// declaration, the field, and its type. Reports it where `type` has no such field.
    private func field(named name: String, at nameRange: SourceRange,
                       of type: RayoType) -> (index: Int, field: DeclaredField, type: RayoType)? {
        // Find the field among the struct's; a value of any other type has none.
        let fields: [DeclaredField] =
            if case .structure(let id) = type { file.declarations.fields(of: id) } else { [] }
        // A name that names no field of the type is reported.
        guard let index = fields.firstIndex(where: { $0.name == name }) else {
            errors.report(.noSuchField(type: typeName(of: type), field: name), at: nameRange)
            return nil
        }

        // A field whose declaration failed was reported there.
        guard let fieldType = fields[index].type else { return nil }
        return (index, fields[index], fieldType)
    }

    /// The whole local called `name`, which the source names at `range`, as a place an expression reads. Reports it
    /// where no local has the name.
    private func local(named name: String, at range: SourceRange) -> TypedPlace? {
        // `_` names no value; it only drops one, or leaves a parameter unnamed.
        if name == "_" {
            errors.report(.underscoreValue, at: range)
            return nil
        }
        switch names.lookUp(name, for: .ordinary) {
        // A local is the place.
        case .inScope(.local(let local)):
            return (CheckedPlace(root: .local(local, range: range)), names[local].type)

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

    /// Checks `left op right`, where the source `spelled` the operator as written, such as `+=` for a
    /// compound assignment's `+`.
    func binary(_ op: CheckedBinaryOperator, _ left: CheckedExpr, _ right: CheckedExpr, spelled: String,
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

private extension CheckedBinaryOperator {
    /// Whether the operator gives a value of its operands' type.
    var isArithmetic: Bool {
        switch self {
        case .add, .subtract, .multiply, .divide, .remainder: true
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual, .and, .or: false
        }
    }
}

/// The rules of a place that an expression reads, which may start from any value and step into any field.
extension ExpressionChecker: PlaceRules {
    func root(_ expr: Expr, holdsFields: Bool) -> TypedPlace? {
        // A name roots the place in the local it names.
        if case .name(let name) = expr.kind { return local(named: name, at: expr.range) }

        // Any other value roots it in a temporary that holds the value, unless the value is a place itself, such as a
        // `copy` of one. A value that failed was reported.
        guard let value = check(expr) else { return nil }
        if case .place(let place) = value.kind { return (place, value.type) }
        return (CheckedPlace(root: .temporary(value)), value.type)
    }

    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool {
        true
    }
}
