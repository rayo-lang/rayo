import RayoSema
import RayoSource

/// Lowers expressions, from the current block on, as the operations that compute them and the operands that hold
/// their values.
extension FunctionLowering {
    /// Lowers `expr` as the computation of its value into `destination`, or, where `destination` is nil, of a value
    /// that is dropped.
    mutating func compute(_ expr: CheckedExpr, into destination: Destination?) {
        // An `if` whose value is dropped runs the branch its condition picks, and computes that branch's value for
        // what it does, so a Void `if` needs no temporary.
        if destination == nil, case .if(let condition, let then, let otherwise) = expr.kind {
            return lowerIf(condition, then, otherwise, into: nil)
        }

        // Any other value is one operation, whose operands are computed first.
        let value = rvalue(of: expr)
        builder.emit(value, into: destination, range: expr.range)
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary unless it is a constant or
    /// a place.
    mutating func operand(of expr: CheckedExpr) -> Operand {
        switch expr.kind {
        // An integer is a constant operand.
        case .intLiteral(let value): .constant(.int(value))
        // So is a Bool.
        case .boolLiteral(let value): .constant(.bool(value))
        // A place that the checker reads is read where it lies, keeping its value.
        case .place(let place): .read(self.place(of: place), at: expr.range)
        // A place that the checker moves gives its value up.
        case .move(let place): .move(self.place(of: place), at: expr.range)
        // `&&` evaluates its right operand only when its left one is true.
        case .binary(.and, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range)
        // `||` evaluates its right operand only when its left one is false.
        case .binary(.or, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range)
        // Any other value, an `if` included, is computed into a temporary.
        case .unary, .binary, .call, .structure, .if:
            .read(temporary(holding: expr), at: expr.range)
        }
    }

    /// Lowers `place` to the IR place it names, computing its root into a new temporary where it is a value that no
    /// local holds.
    mutating func place(of place: CheckedPlace) -> Place {
        let root = switch place.root {
        case .local(let local, _): local
        case .temporary(let value): temporary(holding: value).root
        }
        return Place(root: root, steps: place.steps.map(PlaceStep.init))
    }

    /// Computes `expr` into a new temporary, or, for an `if`, has the branch that runs compute its value there, and
    /// returns the temporary's place.
    private mutating func temporary(holding expr: CheckedExpr) -> Place {
        // An `if` computes its value on the path of the branch that runs.
        if case .if(let condition, let then, let otherwise) = expr.kind {
            return lowerIf(condition, then, otherwise, intoTemporaryOf: expr.type, at: expr.range)
        }
        return lowerIntoTemporary(expr)
    }

    /// Lowers `expr` to the operation that computes its value, computing its operands first.
    private mutating func rvalue(of expr: CheckedExpr) -> Rvalue {
        switch expr.kind {
        // A constant or a place is an operand as it is, and so is `&&`, `||` or an `if`, which lowers to branches.
        case .intLiteral, .boolLiteral, .place, .move, .binary(.and, _, _), .binary(.or, _, _), .if:
            .use(operand(of: expr))
        // A unary operation applies to its operand, computed first.
        case .unary(let op, let value):
            .unary(IRUnaryOperator(op), operand(of: value))
        // The left operand is computed before the right one, in the order the source reads.
        case .binary(let op, let left, let right):
            .binary(IRBinaryOperator(op), operand(of: left), operand(of: right))
        // So are the arguments of a call, from first to last.
        case .call(let callee, let arguments):
            .call(callee, arguments: arguments.map { operand(of: $0) })
        // And the values of a struct's fields, in the order the struct declares them.
        case .structure(let id, let fields):
            .structure(id, fields: fields.map { operand(of: $0) })
        }
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into a new
    /// temporary of `type` at `range`, and returns the temporary's place.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  intoTemporaryOf type: RayoType, at range: SourceRange) -> Place {
        let temporary = builder.newTemporary(type)
        lowerIf(condition, then, otherwise, into: Destination(temporary, at: range))
        return temporary
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into
    /// `destination`, or dropping it where `destination` is nil.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  into destination: Destination?) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let conditionValue = operand(of: condition)
        let thenBlock = builder.newBlock()
        let elseBlock = builder.newBlock()
        let join = builder.newBlock()

        // Each branch runs its statements and computes its value, then goes on to the join.
        builder.end(with: .branch(conditionValue, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then, into: destination)
        builder.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise, into: destination)
        builder.end(with: .goto(join), continuingIn: join)
    }

    /// Lowers `branch`'s statements, then computes its value, where it gives one, into `destination`.
    private mutating func lower(_ branch: CheckedBranch, into destination: Destination?) {
        lower(branch.statements)

        // A branch that gives no value computes none.
        guard let value = branch.value else { return }
        compute(value, into: destination)
    }

    /// Computes `expr` into a new temporary, and returns the temporary's place.
    private mutating func lowerIntoTemporary(_ expr: CheckedExpr) -> Place {
        let temporary = builder.newTemporary(expr.type)
        compute(expr, into: Destination(temporary, at: expr.range))
        return temporary
    }

    /// Lowers `left && right` or `left || right` into branches, and returns an operand that holds the result: `left`
    /// when `left` is `decidingValue`, and otherwise `right`, which is evaluated only then.
    private mutating func shortCircuit(
        _ left: CheckedExpr, _ right: CheckedExpr, decidedWhenLeftIs decidingValue: Bool, range: SourceRange,
    ) -> Operand {
        // The result starts as `left`'s value, which is the result when it is `decidingValue`.
        let result = Destination(builder.newTemporary(.bool), at: range)
        let resultValue = Operand.read(result.place, at: range)
        let leftValue = operand(of: left)
        builder.emit(.use(leftValue), into: result, range: range)

        // A `left` that decides goes on to the join, and any other to a block of its own that evaluates `right`.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)

        // There `right`'s value becomes the result, and both paths meet at the join, where lowering goes on.
        let rightValue = operand(of: right)
        builder.emit(.use(rightValue), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}

private extension PlaceStep {
    init(_ step: CheckedPlaceStep) {
        switch step {
        case .field(let index, _): self = .field(index)
        }
    }
}
