import RayoSema
import RayoSource

/// Lowers expressions, from the current block on, as the operations that compute them and the operands that hold
/// their values.
extension FunctionLowering {
    /// Lowers `expr`, the value of a position that `use`s it, as the computation of its value into `destination`, or,
    /// where `destination` is nil, of a value that is dropped.
    mutating func compute(_ expr: CheckedExpr, into destination: Destination?, as use: ValueUse) {
        // An `if` whose value is dropped runs the branch its condition picks, and computes that branch's value for
        // what it does, so a Void `if` needs no temporary.
        if destination == nil, case .if(let condition, let then, let otherwise) = expr.kind {
            return lowerIf(condition, then, otherwise, into: nil, as: use)
        }

        // Any other value is one operation, whose operands are computed first.
        let value = rvalue(of: expr, as: use)
        builder.emit(value, into: destination, range: expr.range)
    }

    /// Lowers `expr`, the value of a position that `use`s it, to an operand that holds its value, computing it into a
    /// new temporary unless it is a constant or a place.
    mutating func operand(of expr: CheckedExpr, as use: ValueUse) -> Operand {
        switch expr.kind {
        // An integer is a constant operand.
        case .intLiteral(let value): .constant(.int(value))
        case .uintLiteral(let value): .constant(.uint(value))
        // So is a Bool.
        case .boolLiteral(let value): .constant(.bool(value))
        // A place written on its own gives its value up where its position takes it, and keeps it where it reads it.
        case .place(let place):
            switch use {
            case .read: .read(self.place(of: place), at: expr.range)
            case .take: .move(self.place(of: place), at: expr.range)
            }
        // A copy reads the place it copies, whatever its position does with the value.
        case .copy(let place): .read(self.place(of: place), at: expr.range)
        // `&&` evaluates its right operand only when its left one is true.
        case .binary(.and, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range)
        // `||` evaluates its right operand only when its left one is false.
        case .binary(.or, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range)
        // Any other value, an `if` included, is computed into a temporary, from where it is read.
        case .unary, .binary, .call, .if, .arrayLiteral, .filledArray:
            .read(temporary(holding: expr, as: use), at: expr.range)
        }
    }

    /// Lowers `place` to the IR place it names, computing its root into a new temporary where it is a value that no
    /// local holds. The root's value is read, so a place that an `if`'s branch gives keeps its value.
    mutating func place(of place: CheckedPlace) -> Place {
        let root = switch place.root {
        case .local(let local, _): local
        case .temporary(let value): temporary(holding: value, as: .read).root
        }
        return Place(root: root, steps: place.steps.map(PlaceStep.init))
    }

    /// Computes `expr`, the value of a position that `use`s it, into a new temporary, or, for an `if`, has the branch
    /// that runs compute its value there, and returns the temporary's place.
    private mutating func temporary(holding expr: CheckedExpr, as use: ValueUse) -> Place {
        // An `if` computes its value on the path of the branch that runs, which uses it as the `if`'s position does.
        if case .if(let condition, let then, let otherwise) = expr.kind {
            return lowerIf(condition, then, otherwise, intoTemporaryOf: expr.type, at: expr.range, as: use)
        }
        return lowerIntoTemporary(expr)
    }

    /// Lowers `expr`, the value of a position that `use`s it, to the operation that computes its value, computing its
    /// operands first.
    private mutating func rvalue(of expr: CheckedExpr, as use: ValueUse) -> Rvalue {
        switch expr.kind {
        // A constant or a place is an operand as it is, and so is `&&`, `||` or an `if`, which lowers to branches.
        case .intLiteral, .uintLiteral, .boolLiteral, .place, .copy, .binary(.and, _, _), .binary(.or, _, _), .if:
            .operand(operand(of: expr, as: use))
        // A unary operation applies to its operand, computed first.
        case .unary(let op, let value):
            .unary(IRUnaryOperator(op), operand(of: value, as: .read))
        // The left operand is computed before the right one, in the order the source reads.
        case .binary(let op, let left, let right):
            .binary(IRBinaryOperator(op), operand(of: left, as: .read), operand(of: right, as: .read))
        // So are the arguments of a call, from first to last.
        case .call(let callee, let arguments):
            .call(callee, arguments: passed(arguments, to: callee))
        // An array takes its elements, from first to last, as a primary initializer takes its fields.
        case .arrayLiteral(let elements):
            .array(elements.map { operand(of: $0, as: .take) }, of: arrayShape(of: expr).element)
        // A filled array reads its value once, and copies it into each element.
        case .filledArray(let value):
            .filledArray(operand(of: value, as: .read), count: arrayShape(of: expr).count)
        }
    }

    /// The count and element type of the array that `expr` makes.
    private func arrayShape(of expr: CheckedExpr) -> (count: Int, element: RayoType) {
        // Checking gives an array literal or a filled array an array type.
        guard case .array(let count, let element) = expr.type else {
            preconditionFailure("an array literal or a filled array makes an array")
        }
        return (count, element)
    }

    /// Lowers `arguments`, those of a call of `callee`, to what the call passes. A primary initializer takes each, as
    /// its struct's field. Any other function borrows each: a constant is passed as it is, and any other value through
    /// a read access to the place that holds it.
    private mutating func passed(_ arguments: [CheckedExpr], to callee: Callee) -> [CallArgument] {
        if case .function(let id) = callee, case .primaryInitializer = functions[id].kind {
            return arguments.map { .operand(operand(of: $0, as: .take)) }
        }

        // Every argument is evaluated, left to right, before any of the call's borrows begins: they begin together
        // as the call begins, in the order of the arguments.
        let operands = arguments.map { operand(of: $0, as: .read) }
        return operands.map { operand in
            guard case .read(let place, let range) = operand else { return .operand(operand) }
            return .access(builder.begin(Access(.read, .static, to: place, at: range)))
        }
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs, which
    /// the `if`'s position `use`s, into a new temporary of `type` at `range`, and returns the temporary's place.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  intoTemporaryOf type: RayoType, at range: SourceRange, as use: ValueUse) -> Place {
        let temporary = builder.newTemporary(type)
        lowerIf(condition, then, otherwise, into: Destination(temporary, at: range), as: use)
        return temporary
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs, which
    /// the `if`'s position `use`s, into `destination`, or dropping it where `destination` is nil.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  into destination: Destination?, as use: ValueUse) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let conditionValue = operand(of: condition, as: .read)
        let thenBlock = builder.newBlock()
        let elseBlock = builder.newBlock()
        let join = builder.newBlock()

        // Each branch runs its statements and computes its value, then goes on to the join.
        builder.end(with: .branch(conditionValue, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then, into: destination, as: use)
        builder.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise, into: destination, as: use)
        builder.end(with: .goto(join), continuingIn: join)
    }

    /// Lowers `branch`'s statements, then computes its value, where it gives one, into `destination`, which uses it
    /// as the `if`'s position `use`s it.
    private mutating func lower(_ branch: CheckedBranch, into destination: Destination?, as use: ValueUse) {
        lower(branch.statements)

        // A branch that gives no value computes none.
        guard let value = branch.value else { return }
        compute(value, into: destination, as: use)
    }

    /// Computes `expr`, an operation that is neither a place nor an `if`, into a new temporary that an operand reads,
    /// and returns the temporary's place.
    private mutating func lowerIntoTemporary(_ expr: CheckedExpr) -> Place {
        let temporary = builder.newTemporary(expr.type)
        compute(expr, into: Destination(temporary, at: expr.range), as: .read)
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
        let leftValue = operand(of: left, as: .read)
        builder.emit(.operand(leftValue), into: result, range: range)

        // A `left` that decides goes on to the join, and any other to a block of its own that evaluates `right`.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)

        // There `right`'s value becomes the result, and both paths meet at the join, where lowering goes on.
        let rightValue = operand(of: right, as: .read)
        builder.emit(.operand(rightValue), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}

private extension PlaceStep {
    init(_ step: CheckedPlaceStep) {
        self = switch step {
        case .field(let index, _): .field(index)
        }
    }
}
