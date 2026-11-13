import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks expressions: the names they use, their operators' operands, and the types they give.
struct ExpressionChecker {
    /// A borrowed parameter's name, and the name of a place inside it as the source writes it, such as `e.stats.hp`.
    private typealias ParameterPath = (parameter: String, spelling: String)

    let file: FileChecker
    let names: NameScopes
    /// Where a `return`, a `break` and a `continue` in the code being checked leave for.
    let jumps: JumpTargets

    var errors: ErrorList { file.errors }

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
        guard let value = value(of: expr) else { return nil }
        guard let settled = settled(value, toward: expected?.type) else { return nil }
        let used = switch use {
        case .read: settled
        case .take: taken(settled, writtenAs: expr)
        }

        // A value that failed was reported, and a value passes where the position expects no type.
        guard let used, let expected else { return used }
        return expect(used.type, at: used.range, expected) ? used : nil
    }

    /// Checks `expr` on its own, leaving it untyped where it is a literal, or a negation or arithmetic on untyped
    /// values.
    func value(of expr: Expr) -> CheckedValue? {
        switch expr.kind {
        // An integer literal is untyped until its position settles it.
        case .intLiteral(let digits):
            return .untyped(.integer(magnitude: digits, isNegative: false, range: expr.range))

        // So is a negative one, which keeps its sign until the type that holds it is known.
        case .negativeIntLiteral(let digits):
            return .untyped(.integer(magnitude: digits, isNegative: true, range: expr.range))

        // `-` is untyped where its operand is, and `!` is a Bool.
        case .unary(let op, let operand):
            return unary(op, operand, in: expr.range)

        // A binary operator is untyped where it is arithmetic and both its operands are.
        case .binary(let op, let left, let right):
            return binary(op, left, right, in: expr.range)

        // `true` and `false` are Bools.
        case .boolLiteral(let value):
            return .typed(CheckedExpr(kind: .boolLiteral(value), type: .bool, range: expr.range))

        // A name reads the local it names.
        case .name(let name):
            return reference(to: name, at: expr.range).map { .typed($0) }

        // A call reaches one of the functions its name names, or the initializer of the struct it names.
        case .call(let name, let nameRange, let arguments):
            let call = CallChecker(expressions: self).call(name, at: nameRange, arguments, in: expr.range)
            return call.map { .typed($0) }

        // A member of a struct value is one of its fields.
        case .member(let base, let name, let nameRange):
            // A value that failed was reported already.
            guard let value = check(base) else { return nil }
            return field(named: name, at: nameRange, of: value, in: expr.range).map { .typed($0.read) }

        // A `copy` reads the place and leaves its value in it, and it covers the whole `copy place`.
        case .copy(let place):
            return check(place).map { .typed(CheckedExpr(kind: $0.kind, type: $0.type, range: expr.range)) }

        // An `if` read for its value gives the value of the branch that runs.
        case .if:
            return check(expr).map { .typed($0) }
        }
    }

    /// Settles `value` to `type` where it is untyped and fits `type`, and to its default type where it is untyped
    /// otherwise. A typed value is given back as it is.
    func settled(_ value: CheckedValue, toward type: RayoType?) -> CheckedExpr? {
        switch value {
        // A typed value keeps its type.
        case .typed(let typed):
            return typed

        // An untyped value takes `type` where it fits it, and its default type where nothing it fits is offered.
        case .untyped(let untyped):
            let settledType = if let type, untyped.fits(type) { type } else { untyped.defaultType }
            return untyped.settled(to: settledType, named: typeName(of: settledType), reporting: errors)
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

    /// Turns `value`, which `expr` gives, into the value its position takes, which moves a local's value out of it.
    private func taken(_ value: CheckedExpr, writtenAs expr: Expr) -> CheckedExpr? {
        // A `copy` checks to a read of the place it copies, so only a place written bare is moved.
        switch (expr.kind, value.kind) {
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
    /// names it; or nil where the place lies in a `let`, a `var` or a temporary.
    private func parameterPath(to place: CheckedExpr) -> ParameterPath? {
        switch place.kind {
        // A field lies in whatever holds its struct.
        case .field(let structure, let index): parameterPath(toField: index, of: structure)
        // A local is the place's own, which may be a borrowed parameter.
        case .local(let local): names[local].kind == .parameter ? (names[local].name, names[local].name) : nil
        // Any other value is a temporary, which no parameter holds.
        default: nil
        }
    }

    /// The borrowed parameter that the field at `index` of `structure` lies in, and the field as the source names it;
    /// or nil where `structure` lies in no borrowed parameter.
    private func parameterPath(toField index: Int, of structure: CheckedExpr) -> ParameterPath? {
        // A struct that lies in no parameter holds its fields there too.
        guard let holder = parameterPath(to: structure) else { return nil }

        // The field takes its name from the declaration of the struct that holds it.
        guard case .structure(let id) = structure.type else { preconditionFailure("only a struct has fields") }
        return (holder.parameter, holder.spelling + "." + file.declarations.fields(of: id)[index].name)
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
}
