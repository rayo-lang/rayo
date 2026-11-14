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

    /// Checks `expr` as the value of a position that expects `expected` of it where it expects a type. An untyped
    /// value takes the expected type where it fits it, and its default type where it doesn't.
    func check(_ expr: Expr, expecting expected: Expectation? = nil) -> CheckedExpr? {
        // An `if` hands its position to the branch that runs, so each branch's value is checked as the position's.
        if case .if(let ifExpr) = expr.kind {
            return IfChecker(expressions: self).check(ifExpr, in: expr.range, expecting: expected)
        }

        // Any other value is checked on its own, and settled toward the type the position expects.
        // A value that failed was reported.
        guard let value = value(of: expr) else { return nil }
        // So was a literal that the type it settles to can't hold.
        guard let settled = settled(value, toward: expected?.type) else { return nil }

        // A value passes where the position expects no type.
        guard let expected else { return settled }
        return expect(settled.type, at: settled.range, expected) ? settled : nil
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

        // A name reads the local it names, a member a field of the place its base names or the count of the array its
        // base names, and an element the element of the array its base names.
        case .name, .member, .element:
            place(expr, under: self).map { .typed(value(at: $0, in: expr.range)) }

        // A call reaches one of the functions its callee names, or makes the struct it names. A call of an implicit
        // member waits for its position to give the type whose member it calls.
        case .call(let callee, let arguments):
            CallChecker(expressions: self).call(callee, arguments, in: expr.range)

        // So does an implicit member that isn't called.
        case .implicitMember(let name):
            .implicitMember(ImplicitMember(name: name, nameRange: expr.range, arguments: nil, range: expr.range))

        // A `copy` copies the value of the place it names, and covers the whole `copy place`.
        case .copy(let copied):
            place(copied, under: self).map {
                .typed(CheckedExpr(kind: .copy($0.place), type: $0.type, range: expr.range))
            }

        // An `if` read for its value gives the value of the branch that runs.
        case .if:
            check(expr).map { .typed($0) }

        // An array literal waits for its position to give it a type, which its elements settle to.
        case .arrayLiteral(let elements):
            arrayLiteral(of: elements, in: expr.range)
        }
    }

    /// Settles `value` to `type` where it is untyped and fits `type`, and to its default type where it is untyped
    /// otherwise. An array literal settles to `type` where it is an array, and to the type its elements give
    /// otherwise. An implicit member names a member of `type`. A typed value is given back as it is.
    func settled(_ value: CheckedValue, toward type: RayoType?) -> CheckedExpr? {
        switch value {
        case .typed(let typed): typed
        case .untyped(let untyped): settled(untyped, toward: type)
        case .arrayLiteral(let literal): ArrayLiteralChecker(expressions: self).settled(literal, toward: type)
        case .implicitMember(let member): ImplicitMemberChecker(expressions: self).settled(member, toward: type)
        }
    }

    /// Settles each of `values` that checked to its default type where it is untyped, so the literals in it that
    /// their default type can't hold are reported, where the expression that holds them fails for another reason.
    /// An array literal's elements are settled so, and not the literal itself, whose type the failed expression
    /// would have given; so are an implicit member's arguments, and not the member.
    func reportSettlingErrors(of values: [CheckedValue?]) {
        for value in values {
            switch value {
            case .untyped(let untyped)?: _ = settled(untyped, toward: nil)
            case .arrayLiteral(let literal)?: reportSettlingErrors(of: literal.elements)
            case .implicitMember(let member)?: reportSettlingErrors(of: member.argumentValues)
            case .typed?, nil: break
            }
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

    /// Checks each of `elements`, those of the array literal at `range`, on its own, so that each settles to the
    /// element type of the array the literal settles to.
    private func arrayLiteral(of elements: [Expr], in range: SourceRange) -> CheckedValue? {
        // Every element is checked, so each one's errors are reported, before any failure fails the literal.
        let values = elements.map { value(of: $0) }
        let checked = values.compactMap { $0 }
        // An element that failed was reported, and the others' literals are settled for their own errors.
        guard checked.count == values.count else {
            reportSettlingErrors(of: values)
            return nil
        }
        return .arrayLiteral(ArrayLiteral(elements: checked, range: range))
    }

    /// The value of `place`, which the source names at `range`. A place that is an array's count and nothing more
    /// gives the count itself.
    private func value(at place: TypedPlace, in range: SourceRange) -> CheckedExpr {
        if place.place.steps.isEmpty, case .temporary(let value) = place.place.root, case .arrayCount = value.kind {
            return value
        }
        return CheckedExpr(kind: .place(place.place), type: place.type, range: range)
    }

    /// Checks `op operandExpr`, which is untyped where `op` is `-` and its operand is untyped.
    private func unary(_ op: UnaryOperator, _ operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        switch op {
        case .negate: negation(of: operandExpr, in: range)
        case .not: not(operandExpr, in: range)
        }
    }

    /// Checks `-operandExpr`, which negates an untyped operand to an untyped value, and a typed one only where it is
    /// an integer, to a value of its type.
    private func negation(of operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        // An operand that failed was reported already.
        guard let operand = value(of: operandExpr) else { return nil }
        return switch operand {
        // An untyped operand gives an untyped negation.
        case .untyped(let untyped): .untyped(.negation(untyped, range: range))
        case .typed(let typed): negation(of: typed, in: range)
        // An array literal settles to the type its elements give, which no negation takes, and an implicit member
        // to no type.
        case .arrayLiteral, .implicitMember: settled(operand, toward: nil).flatMap { negation(of: $0, in: range) }
        }
    }

    /// Checks `-operand`, where the operand is typed, which negates it to a value of its type where it is an integer.
    private func negation(of operand: CheckedExpr, in range: SourceRange) -> CheckedValue? {
        // An operand of a type that isn't an integer is reported.
        guard operand.type.isInteger else {
            errors.report(.integerOperand(op: UnaryOperator.negate.rawValue, found: typeName(of: operand.type)),
                          at: range)
            return nil
        }
        return .typed(CheckedExpr(kind: .unary(.negate, operand), type: operand.type, range: range))
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

        // The operator is checked as what it means.
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

    /// Checks an expression that names a place, such as `e.stats.hp` or `e.party[i]`, under the rules of the position
    /// it stands in: first where the place starts, then each field or element it goes into. Returns nil once it has
    /// reported a mistake in any of them.
    func place(_ expr: Expr, under rules: some PlaceRules) -> TypedPlace? {
        place(expr, under: rules, holdsParts: false)
    }

    /// Checks an expression that names a place under the given rules. The flag says whether the place goes on into
    /// a field or an element of it, as the base of a longer place does.
    private func place(_ expr: Expr, under rules: some PlaceRules, holdsParts: Bool) -> TypedPlace? {
        switch expr.kind {
        // A member names a field of the place its base names, or its count, and an element steps into an element of
        // it.
        case .member(let base, let name, let nameRange):
            member(named: name, at: nameRange, of: base, in: expr.range, under: rules)
        case .element(let base, let index):
            element(at: index, of: base, in: expr.range, under: rules)

        // Anything else is the place's root.
        default:
            rules.root(expr, holdsParts: holdsParts)
        }
    }

    /// Checks `base.name`, which the source writes at `range`: the count of the array its base names where `name` is
    /// `count`, and otherwise the field called `name` of the place its base names. Reports any other member of an
    /// array.
    private func member(named name: String, at nameRange: SourceRange, of base: Expr, in range: SourceRange,
                        under rules: some PlaceRules) -> TypedPlace? {
        // A base that failed was reported.
        guard let holder = place(base, under: rules, holdsParts: true) else { return nil }

        // The one member an array's value has is its count, and it has no fields.
        if case .array(let count, _) = holder.type {
            guard name == "count" else {
                errors.report(.noSuchMember(type: typeName(of: holder.type), name: name), at: nameRange)
                return nil
            }
            // A position whose rules don't admit a count was reported.
            guard rules.admitsCount(at: nameRange) else { return nil }

            // A count is a value that no local holds, so it roots a place as a call's result does.
            let value = CheckedExpr(kind: .arrayCount(holder.place, count: count), type: .uint, range: range)
            return (CheckedPlace(root: .temporary(value)), .uint)
        }

        // A field that the holder doesn't have, or that the rules don't admit, was reported.
        guard let (index, field, type) = field(named: name, at: nameRange, of: holder.type),
              rules.admits(field, at: nameRange)
        else { return nil }
        return (holder.place.appending(.field(index, range: range)), type)
    }

    /// Checks `base[indexExpr]`, the element at a UInt index of the array its base names, which the source writes at
    /// `range`. Reports a base that isn't an array, and an index that isn't a UInt.
    private func element(at indexExpr: Expr, of base: Expr, in range: SourceRange,
                         under rules: some PlaceRules) -> TypedPlace? {
        // A place whose rules don't admit an element was reported.
        guard rules.admitsElement(at: range) else { return nil }

        // The base and the index are both checked, so each one's errors are reported; a literal index is a UInt.
        let holder = place(base, under: rules, holdsParts: true)
        let index = check(indexExpr, expecting: Expectation(.uint) { _, found in .indexNotUInt(found: found) })
        guard let holder else { return nil }

        // Only an array has elements.
        guard case .array(let count, let element) = holder.type else {
            errors.report(.notIndexable(found: typeName(of: holder.type)), at: base.range)
            return nil
        }

        // An index that failed was reported.
        guard let index else { return nil }
        return (holder.place.appending(.element(index: index, count: count, range: range)), element)
    }

    /// Finds a field by its name in a value's type: its position in the struct's declaration, the field, and its
    /// type. Reports a name that names no field of the type.
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

        // A local, a function or a struct whose declaration failed was reported there.
        case .inScope(.failed), .failed:
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
        // Operands the operator doesn't take were reported.
        guard let result = resultType(of: op, left, right, spelled: spelled, in: range) else { return nil }
        return CheckedExpr(kind: .binary(op, left, right), type: result, range: range)
    }

    /// The type `left op right` gives, or nil after reporting operands that `op`, which the source `spelled` as
    /// written, doesn't take.
    private func resultType(of op: CheckedBinaryOperator, _ left: CheckedExpr, _ right: CheckedExpr,
                            spelled: String, in range: SourceRange) -> RayoType? {
        switch op {
        // Arithmetic takes two integers of one type, and gives a value of that type.
        case .add, .subtract, .multiply, .divide, .remainder:
            integerOperands(of: spelled, left, right, in: range) ? left.type : nil

        // An ordering takes two integers of one type, and gives a Bool.
        case .less, .lessEqual, .greater, .greaterEqual:
            integerOperands(of: spelled, left, right, in: range) ? .bool : nil

        // `&&` and `||` take two Bools, and give a Bool.
        case .and, .or:
            operands(of: spelled, left, right, are: .bool, in: range) ? .bool : nil

        // `==` and `!=` take two values of one type that compares, and give a Bool.
        case .equal, .notEqual:
            comparable(spelled, left, right, in: range) ? .bool : nil
        }
    }

    /// Whether `==` or `!=`, as the source `spelled` it, compares `left` with `right`, reporting it when it doesn't.
    private func comparable(_ spelled: String, _ left: CheckedExpr, _ right: CheckedExpr,
                            in range: SourceRange) -> Bool {
        // Comparing values of two types is reported.
        guard left.type == right.type else {
            let code = ErrorCode.operandsDiffer(
                op: spelled, left: typeName(of: left.type), right: typeName(of: right.type),
            )
            errors.report(code, at: range)
            return false
        }

        // Comparing values of a type that doesn't compare is reported.
        guard isComparable(left.type) else {
            errors.report(.incomparable(op: spelled, type: typeName(of: left.type)), at: range)
            return false
        }
        return true
    }

    /// Whether `==` and `!=` compare values of `type`.
    private func isComparable(_ type: RayoType) -> Bool {
        switch type {
        // Integers and Bools compare.
        case .int, .uint, .bool: true
        // A Void value holds nothing to compare, and a struct and an array have no `==`.
        case .void, .structure, .array: false
        }
    }

    /// Whether `left` and `right` are integers of one type, reporting it when they aren't.
    private func integerOperands(of spelled: String, _ left: CheckedExpr, _ right: CheckedExpr,
                                 in range: SourceRange) -> Bool {
        // Two integers of one type pass.
        if left.type == right.type && left.type.isInteger { return true }

        // No integer type converts to another, so two integers of different types are reported as such.
        let (leftName, rightName) = (typeName(of: left.type), typeName(of: right.type))
        let code: ErrorCode = if left.type.isInteger && right.type.isInteger {
            .operandsDiffer(op: spelled, left: leftName, right: rightName)
        } else {
            .integerOperands(op: spelled, left: leftName, right: rightName)
        }
        errors.report(code, at: range)
        return false
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

/// The rules of a place that an expression reads, which may start from any value, step into any field or element, and
/// name any array's count.
extension ExpressionChecker: PlaceRules {
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        // A name roots the place in the local it names.
        if case .name(let name) = expr.kind { return local(named: name, at: expr.range) }

        // Any other value roots it in a temporary that holds the value, unless the value is a place itself, such as a
        // `copy` of one. A value that failed was reported.
        guard let value = check(expr) else { return nil }
        switch value.kind {
        case .place(let place), .copy(let place): return (place, value.type)
        default: return (CheckedPlace(root: .temporary(value)), value.type)
        }
    }

    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool {
        true
    }

    func admitsElement(at range: SourceRange) -> Bool {
        true
    }

    func admitsCount(at nameRange: SourceRange) -> Bool {
        true
    }
}
