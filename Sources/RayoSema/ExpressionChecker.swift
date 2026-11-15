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
        // A value that failed was reported.
        guard let value = value(of: expr) else { return nil }
        guard let expected else { return settled(value, toward: nil) }
        return settled(value, expecting: expected)
    }

    /// Checks `expr` on its own, leaving it to wait for its position's type where it is an untyped value, an array
    /// literal, an implicit member, or an `if`.
    func value(of expr: Expr) -> CheckedValue? {
        switch expr.kind {
        // An integer literal is untyped until its position settles it.
        case .intLiteral(let digits):
            .waiting(UntypedValue.integer(magnitude: digits, isNegative: false, range: expr.range))

        // So is a negative one, which keeps its sign until the type that holds it is known.
        case .negativeIntLiteral(let digits):
            .waiting(UntypedValue.integer(magnitude: digits, isNegative: true, range: expr.range))

        // `-` is untyped where its operand is, and `!` is a Bool.
        case .unary(let op, let operand):
            unary(op, operand, in: expr.range)

        // A binary operator is untyped where it is arithmetic and both its operands are.
        case .binary(let op, let left, let right):
            binary(op, left, right, in: expr.range)

        // `true` and `false` are Bools.
        case .boolLiteral(let value):
            .typed(CheckedExpr(kind: .boolLiteral(value), type: .bool, range: expr.range))

        // A name reads the local it names, and an element the element of the array its base names.
        case .name, .element:
            place(expr, under: self).map {
                .typed(CheckedExpr(kind: .place($0.place), type: $0.type, range: expr.range))
            }

        // A member reads a property of the value its base names: a field, or a value such as an array's count.
        case .member(let base, let name, let nameRange):
            member(named: name, at: nameRange, of: base, in: expr.range, under: self).map { .typed($0) }

        // A call reaches one of the functions its callee names, or one of the initializers of the type it names. A
        // call of an implicit member waits for its position to give the type whose member it calls.
        case .call(let callee, let arguments):
            CallChecker(expressions: self).call(callee, arguments, in: expr.range)

        // So does an implicit member that isn't called.
        case .implicitMember(let name):
            .waiting(ImplicitMember(name: name, nameRange: expr.range, arguments: nil, range: expr.range))

        // A `copy` copies the value of the place it names, and covers the whole `copy place`.
        case .copy(let copied):
            place(copied, under: self).map {
                .typed(CheckedExpr(kind: .copy($0.place), type: $0.type, range: expr.range))
            }

        // An `if` read for its value gives the value of the branch that runs, so its branches' values wait for its
        // position as the `if` does.
        case .if(let ifExpr):
            IfChecker(expressions: self).value(of: ifExpr, in: expr.range).map { .waiting($0) }

        // An array literal waits for its position to give it a type, which its elements settle to.
        case .arrayLiteral(let elements):
            arrayLiteral(of: elements, in: expr.range)
        }
    }

    /// Settles `value` toward `type`, where it waits for one. A typed value is given back as it is.
    func settled(_ value: CheckedValue, toward type: RayoType?) -> CheckedExpr? {
        switch value {
        case .typed(let typed): typed
        case .waiting(let waiting): waiting.settled(toward: type, by: self)
        }
    }

    /// Reports the errors of each of `values` that waits for a type, where the expression that holds them fails for
    /// another reason and so never settles them.
    func reportSettlingErrors(of values: [CheckedValue?]) {
        for case .waiting(let waiting)? in values {
            waiting.reportErrors(by: self)
        }
    }

    /// Settles `value` to the type `expected` names, reporting where it can't take that type.
    func settled(_ value: CheckedValue, expecting expected: Expectation) -> CheckedExpr? {
        switch value {
        case .typed(let typed): fitted(typed, to: expected)
        case .waiting(let waiting): waiting.settled(expecting: expected, by: self)
        }
    }

    /// Makes `value` stand where a position expects the type `expected` names, reporting its mismatch where it can't.
    func fitted(_ value: CheckedExpr, to expected: Expectation) -> CheckedExpr? {
        // A value that fits stands there as the fit gives it.
        if let fitted = TypeFit.fitted(value, to: expected.type) { return fitted }
        reportMismatch(of: value.type, at: value.range, expected)
        return nil
    }

    /// Whether a value of `type`, which the source gives at `range` but no expression holds, such as the Void a
    /// branch ends in, fits the type `expected` names, reporting its mismatch when it doesn't.
    func fits(_ type: RayoType, at range: SourceRange, _ expected: Expectation) -> Bool {
        if TypeFit.fits(type, expected.type) { return true }
        reportMismatch(of: type, at: range, expected)
        return false
    }

    /// Reports a value of `type` at `range`, where a position expects the type `expected` names, with its error.
    private func reportMismatch(of type: RayoType, at range: SourceRange, _ expected: Expectation) {
        errors.report(expected.mismatch(typeName(of: expected.type), typeName(of: type)), at: range)
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
        return .waiting(ArrayLiteral(elements: checked, range: range))
    }

    /// Checks `op operandExpr`, which is untyped where `op` is `-` and its operand is untyped.
    private func unary(_ op: UnaryOperator, _ operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        switch op {
        case .negate: negation(of: operandExpr, in: range)
        case .not: not(operandExpr, in: range)
        }
    }

    /// Checks `-operandExpr`, which negates an untyped operand to an untyped value, and a typed one only where it is
    /// signed, to a value of its type.
    private func negation(of operandExpr: Expr, in range: SourceRange) -> CheckedValue? {
        // An operand that failed was reported already.
        guard let operand = value(of: operandExpr) else { return nil }
        return switch operand {
        // An untyped operand gives an untyped negation.
        case .waiting(let untyped as UntypedValue): .waiting(untyped.negated(at: range))
        case .typed(let typed): negation(of: typed, in: range)
        // Any other value that waits settles as it would where its position gives no type.
        case .waiting: settled(operand, toward: nil).flatMap { negation(of: $0, in: range) }
        }
    }

    /// Checks `-operand`, where the operand is typed, which negates it to a value of its type where it is signed.
    private func negation(of operand: CheckedExpr, in range: SourceRange) -> CheckedValue? {
        // Negating an unsigned value overflows for every value but 0, so only a signed type has `-`.
        guard operand.type.isSigned else {
            errors.report(.signedOperand(op: UnaryOperator.negate.rawValue, found: typeName(of: operand.type)),
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
        if case .waiting(let untypedLeft as UntypedValue) = left,
           case .waiting(let untypedRight as UntypedValue) = right, checkedOp.isArithmetic {
            return .waiting(UntypedValue.arithmetic(checkedOp, untypedLeft, untypedRight, range: range))
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
        // A member names a field of the place its base names, or a value property, whose value the rules may let a
        // place hold.
        case .member(let base, let name, let nameRange):
            memberPlace(named: name, at: nameRange, of: base, in: expr.range, under: rules)

        // An element steps into an element of the place its base names.
        case .element(let base, let index):
            element(at: index, of: base, in: expr.range, under: rules)

        // A bare name roots the place in what it names.
        case .name(let name):
            place(named: name, at: expr.range, under: rules, holdsParts: holdsParts)

        // Anything else is the place's root.
        default:
            rules.root(expr, holdsParts: holdsParts)
        }
    }

    /// Checks a bare name, which the source writes at `range`, as a place under the given rules: a local, or a field
    /// of `self`, which is the same place as `self.name`. Reports a name that names no place, and a place the rules
    /// refuse. The flag says whether the place goes on into a field or an element of it.
    private func place(named name: String, at range: SourceRange, under rules: some PlaceRules,
                       holdsParts: Bool) -> TypedPlace? {
        // `_` names no place; it only drops a value, or leaves a parameter unnamed.
        if name == "_" { return noPlace(reporting: rules.error(naming: .underscore, name), at: range) }

        return switch names.lookUp(name, for: .ordinary) {
        // A local is the place's root.
        case .inScope(.local(let local)):
            localPlace(local, at: range, under: rules, holdsParts: holdsParts)

        // A field of `self` goes on from `self`, so the rules check both, as they would in `self.name`.
        case .instanceField(let selfParameter, let index, let field):
            instanceFieldPlace(index, field, of: selfParameter, at: range, under: rules)

        // A local, a function or a type whose declaration failed was reported there.
        case .inScope(.failed), .failed:
            nil

        // A function or a type is no place.
        case .functions:
            noPlace(reporting: rules.error(naming: .function, name), at: range)
        case .type:
            noPlace(reporting: rules.error(naming: .type, name), at: range)

        // Nothing has the name.
        case nil:
            noPlace(reporting: .notDeclared(name: name), at: range)
        }
    }

    /// The whole of `local`, which the source names at `range`, as a place under the given rules, or nil where they
    /// refuse it. The flag says whether the place goes on into a field or an element of it.
    private func localPlace(_ local: LocalID, at range: SourceRange, under rules: some PlaceRules,
                            holdsParts: Bool) -> TypedPlace? {
        guard rules.admits(local, at: range, holdsParts: holdsParts) else { return nil }
        return (CheckedPlace(root: .local(local, range: range)), names[local].type)
    }

    /// The field at `index` of the `self` that `selfParameter` holds, which the source names by its bare name at
    /// `range`, as a place under the given rules, or nil where they refuse `self` or the field.
    private func instanceFieldPlace(_ index: Int, _ field: Field, of selfParameter: LocalID, at range: SourceRange,
                                    under rules: some PlaceRules) -> TypedPlace? {
        guard let holder = localPlace(selfParameter, at: range, under: rules, holdsParts: true) else { return nil }
        guard rules.admits(field, at: range) else { return nil }
        return (holder.place.appending(.field(index, range: range)), field.type)
    }

    /// Reports why a bare name names no place, and returns nil in place of the place.
    private func noPlace(reporting error: ErrorCode, at range: SourceRange) -> TypedPlace? {
        errors.report(error, at: range)
        return nil
    }

    /// Checks `base.name`, which the source writes at `range`, as a place under the given rules: the place of a
    /// field, or, where the rules let a place hold it, of a value property's value.
    private func memberPlace(named name: String, at nameRange: SourceRange, of base: Expr, in range: SourceRange,
                             under rules: some PlaceRules) -> TypedPlace? {
        // A member that failed was reported.
        guard let member = member(named: name, at: nameRange, of: base, in: range, under: rules) else { return nil }
        if case .place(let place) = member.kind { return (place, member.type) }
        return rules.place(holding: member, at: nameRange)
    }

    /// Checks `base.name`, which the source writes at `range`, under the rules of the position it stands in: the
    /// property called `name` of the value its base names, as the value it gives. A field gives the part of the base's
    /// place that holds it, and a value property, such as an array's count, the value it computes. Reports a name
    /// that names no property of the base's type.
    private func member(named name: String, at nameRange: SourceRange, of base: Expr, in range: SourceRange,
                        under rules: some PlaceRules) -> CheckedExpr? {
        // A base that failed was reported.
        guard let holder = place(base, under: rules, holdsParts: true) else { return nil }

        switch file.declarations.member(named: name, of: holder.type) {
        // A field is the part of its base's place that holds it, where the rules admit it here; one they don't was
        // reported.
        case .field(let index, let field)?:
            guard rules.admits(field, at: nameRange) else { return nil }
            let place = holder.place.appending(.field(index, range: range))
            return CheckedExpr(kind: .place(place), type: field.type, range: range)

        // An array's count is a UInt that the array's type fixes.
        case .count(let count)?:
            return CheckedExpr(kind: .arrayCount(holder.place, count: count), type: .uint, range: range)

        // A type's initializers are no property of a value of it, and nor is a name the type lacks.
        case .initializers?, nil:
            reportNoProperty(named: name, at: nameRange, of: holder.type)
            return nil
        }
    }

    /// Checks `base[indexExpr]`, the element at a UInt index of the array its base names, which the source writes at
    /// `range`. Reports a base that isn't an array, an index that isn't a UInt, and an integer literal index past the
    /// array's end.
    private func element(at indexExpr: Expr, of base: Expr, in range: SourceRange,
                         under rules: some PlaceRules) -> TypedPlace? {
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

        // An integer literal is known as the program is checked, so one past the array's end is an error here; any
        // other index is checked as the program runs.
        if case .integerLiteral(let value, _) = index.kind, value >= count {
            errors.report(.indexOutOfRange(index: UInt64(value), type: typeName(of: holder.type)), at: index.range)
            return nil
        }

        return (holder.place.appending(.element(index: index, count: count, range: range)), element)
    }

    /// Reports that a value of `type` has no property called `name`, which the source writes at `nameRange`. An
    /// array has a property besides fields, its count, so the error names the property a member of it; any other
    /// type's properties are fields alone.
    private func reportNoProperty(named name: String, at nameRange: SourceRange, of type: RayoType) {
        let code: ErrorCode = if case .array = type {
            .noSuchMember(type: typeName(of: type), name: name)
        } else {
            .noSuchField(type: typeName(of: type), field: name)
        }
        errors.report(code, at: nameRange)
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
        // Every scalar compares: an integer or a Bool.
        case .scalar: true
        // A Void value holds nothing to compare, and a struct and an array have no `==`.
        case .void, .named, .array: false
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
        if TypeFit.fits(left.type, type) && TypeFit.fits(right.type, type) { return true }
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

/// The rules of a place that an expression reads, which may start from any value, step into any field, and go on
/// from any value property, whose value it holds as a call's result.
extension ExpressionChecker: PlaceRules {
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        // A value roots the place in a temporary that holds the value, unless the value is a place itself. A `copy`
        // of a place is a value like any other, so a part taken from it moves out of the copy and leaves the place
        // whole. A value that failed was reported.
        guard let value = check(expr) else { return nil }
        let place = if case .place(let place) = value.kind { place } else { CheckedPlace(root: .temporary(value)) }
        return (place, value.type)
    }

    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool {
        true
    }

    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        switch nonPlace {
        case .underscore: .underscoreValue
        case .function: .functionAsValue(name: name)
        case .type: .typeAsValue(name: name)
        }
    }

    func admits(_ field: Field, at nameRange: SourceRange) -> Bool {
        true
    }

    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace? {
        (CheckedPlace(root: .temporary(property)), property.type)
    }
}
