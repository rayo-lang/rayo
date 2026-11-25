import RayoCheckedProgram
import RayoSource

/// Lowers expressions, from the current block on, as the operations that compute them and the operands that hold
/// their values.
extension FunctionLowering {
    /// Lowers `expr` as the computation of its value into `destination`, or, where `destination` is nil, of a value
    /// that is dropped.
    mutating func compute(_ expr: CheckedExpr, into destination: Destination?) {
        compute(expr, into: destination, borrowsPlaces: expr.borrowsPlaces)
    }

    /// Lowers `expr` as `compute(_:into:)` does, where `borrowsPlaces` says whether it borrows places. An `if` passes
    /// this on to its branches, which borrow places exactly when it does, so a nested `if` isn't walked again.
    private mutating func compute(_ expr: CheckedExpr, into destination: Destination?, borrowsPlaces: Bool) {
        switch expr.kind {
        // A borrow makes the value of the local it declares depend on what it borrows, so it needs the local.
        case .place(let place, .borrow):
            // Checking gives only a `ref let` a place it borrows.
            guard let destination else { preconditionFailure("only a 'ref let' borrows a place") }
            borrow(place, at: expr.range, into: destination)

        // An `if` whose value is dropped runs the branch its condition picks, and computes that branch's value for
        // what it does, so a Void `if` needs no temporary. An `if` whose branches borrow places has the branch that
        // runs compute its value into the `ref let` itself, so the local depends on the access of whichever branch ran.
        case .if(let condition, let then, let otherwise) where destination == nil || borrowsPlaces:
            lowerIf(condition, then, otherwise, into: destination, borrowsPlaces: borrowsPlaces)

        // Any other value is one operation, whose operands are computed first.
        default:
            builder.emit(rvalue(of: expr), into: destination, range: expr.range)
        }
    }

    /// Lowers the borrow of `place`, which the source names at `range`, into `destination`, the local of the `ref let`
    /// that borrows it. The place is read through a read access, which the local's value then depends on, so the
    /// access lasts for as long as the local is used.
    private mutating func borrow(_ place: CheckedPlace, at range: SourceRange, into destination: Destination) {
        // Checking reports a place that no local holds given to a `ref let`, which has no place to refer to.
        guard place.local != nil else { preconditionFailure("only a place that a local holds is borrowed") }

        let borrowed = self.place(of: place)
        let access = builder.begin(Access(.read, to: borrowed, at: range))
        builder.emit(.operand(.read(borrowed, at: range)), into: destination, range: range)
        builder.emit(.depend(destination.place, on: access))
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary unless it is a constant or
    /// a place.
    mutating func operand(of expr: CheckedExpr) -> Operand {
        switch expr.kind {
        // An integer is a constant operand.
        case .integerLiteral(let value, let type): .constant(.integer(value, type))
        // So is a Bool.
        case .boolLiteral(let value): .constant(.bool(value))
        // A place written on its own is read where its position copies its value or is lent it, and moved out of
        // where its position takes the value.
        case .place(let place, let use):
            switch use {
            case .copy, .lend: .read(self.place(of: place), at: expr.range)
            case .move: .move(self.place(of: place), at: expr.range)
            case .borrow: preconditionFailure("a borrow is lowered into the local it declares, as no operand")
            case .lendForChange: preconditionFailure("a place lent for change is passed as its argument, as no operand")
            }
        // An array's count is a constant, which the type of the array it counts fixes.
        case .arrayCount(let place, let count): arrayCount(of: place, fixedAt: count, at: expr.range)
        // `&&` evaluates its right operand only when its left one is true.
        case .binary(.and, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range)
        // `||` evaluates its right operand only when its left one is false.
        case .binary(.or, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range)
        // Any other value, an `if`, a copy or a consume included, is computed into a temporary, from where it is read.
        // So a copy is made, and a move made, where the source writes it: a later operand that changes the copied
        // place leaves the copy as it was, and one that uses the consumed place finds it moved.
        case .copy, .consume, .unary, .binary, .call, .if, .arrayLiteral, .filledArray:
            .read(temporary(holding: expr), at: expr.range)
        }
    }

    /// Lowers `place` to the IR place it names, computing its root into a new temporary where it is a value that no
    /// local holds, then each index of an element it steps into, in the order of its steps. The root's value is read,
    /// so a place that an `if`'s branch gives keeps its value.
    mutating func place(of place: CheckedPlace) -> Place {
        let root = switch place.root {
        case .local(let local, _): local
        case .temporary(let value): temporary(holding: value).root
        }

        var lowered = Place(root: root)
        for step in place.steps {
            lowered = lowered.appending(self.step(step))
        }
        return lowered
    }

    /// Lowers `step`, computing the index of an element it steps into where the IR can't write it.
    private mutating func step(_ step: CheckedPlaceStep) -> PlaceStep {
        switch step {
        case .field(let index, _): .field(index)
        case .element(let index, let count, _): elementStep(at: index, below: count)
        }
    }

    /// Lowers the step into the element at `index` of an array of `count` elements: one the IR writes where `index`
    /// is a UInt literal inside the array, and otherwise one at a new temporary that holds the index, which is
    /// computed once and checked against `count` where the source writes it.
    private mutating func elementStep(at index: CheckedExpr, below count: Int) -> PlaceStep {
        // A literal index inside the array needs no check. It names an element apart from those at other literals.
        // A literal outside the array was reported, and is checked as any other index is, as the trap it would reach.
        if case .integerLiteral(let value, _) = index.kind, (0..<Int128(count)).contains(value) {
            return .element(Int(value))
        }

        let checked = builder.newTemporary(.uint)
        let value = operand(of: index)
        builder.emit(.index(value, below: count), into: Destination(checked, at: index.range), range: index.range)
        return .elementAt(checked.root)
    }

    /// Lowers the count of the array that `place` holds, which the source writes at `range`, to the constant
    /// `count`. The array is read where the count is, and the read dropped, so the count is a use of the array, which
    /// must hold a value, though no code loads any of it. What naming the place does runs first, such as a call that
    /// gives its root or an index it checks.
    private mutating func arrayCount(of place: CheckedPlace, fixedAt count: Int, at range: SourceRange) -> Operand {
        let array = self.place(of: place)
        builder.emit(.operand(.read(array, at: range)), into: nil, range: range)
        return .constant(.integer(Int128(count), .uint))
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
        case .integerLiteral, .boolLiteral, .place, .arrayCount, .binary(.and, _, _), .binary(.or, _, _), .if:
            .operand(operand(of: expr))
        // A copy reads the place it copies, whatever its position does with the value.
        case .copy(let place):
            .operand(.read(self.place(of: place), at: expr.range))
        // A consume moves the value out of the place it names, whatever its position does with the value.
        case .consume(let place):
            .operand(.move(self.place(of: place), at: expr.range))
        // A unary operation applies to its operand, computed first.
        case .unary(let op, let value):
            .unary(IRUnaryOperator(op), operand(of: value))
        // The left operand is computed before the right one, in the order the source reads.
        case .binary(let op, let left, let right):
            .binary(IRBinaryOperator(op), operand(of: left), operand(of: right))
        // So are the arguments of a call, from first to last.
        case .call(let callee, let arguments):
            .call(callee, arguments: passed(arguments))
        // An array takes its elements, from first to last.
        case .arrayLiteral(let elements):
            .array(elements.map { operand(of: $0) }, of: arrayShape(of: expr).element)
        // A filled array computes its value once, and copies it into each element.
        case .filledArray(let value):
            .filledArray(operand(of: value), count: arrayShape(of: expr).count)
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

    /// Lowers `arguments`, those of a call, to what the call passes, as each parameter's convention takes it: an owned
    /// value as an operand that takes it, a borrowed value as a constant or a read access to the place that holds it,
    /// and a mutable place as a modify access to it.
    private mutating func passed(_ arguments: [CheckedArgument]) -> [CallArgument] {
        // Every argument is evaluated, left to right, before any of the call's accesses begins: they begin together
        // as the call begins, in the order of the arguments.
        let evaluated = arguments.map { evaluate($0) }
        return evaluated.map { argument in
            switch argument {
            case .value(let operand): .operand(operand)
            case .place(let place, let range, let kind):
                .access(builder.begin(Access(kind, to: place, at: range)))
            }
        }
    }

    /// Evaluates `argument`, and returns what the call passes for it, before the call's accesses begin.
    private mutating func evaluate(_ argument: CheckedArgument) -> EvaluatedArgument {
        switch argument {
        case .borrowed(let value): .borrowing(operand(of: value))
        case .owned(let value): .value(operand(of: value))
        case .mutable(let place): .place(self.place(of: place), at: place.range, .modify)
        }
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into a
    /// new temporary of `type` at `range`, and returns the temporary's place.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  intoTemporaryOf type: RayoType, at range: SourceRange) -> Place {
        let temporary = builder.newTemporary(type)
        // Only a `ref let` borrows places, into its own local, so no branch whose value a temporary holds borrows one.
        lowerIf(condition, then, otherwise, into: Destination(temporary, at: range), borrowsPlaces: false)
        return temporary
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into
    /// `destination`, or dropping it where `destination` is nil. Where the branches borrow places, each computes its
    /// value straight into the `ref let`'s local that `destination` names.
    private mutating func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                  into destination: Destination?, borrowsPlaces: Bool) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let conditionValue = operand(of: condition)
        let thenBlock = builder.newBlock()
        let elseBlock = builder.newBlock()
        let join = builder.newBlock()

        // Each branch runs its statements and computes its value, then goes on to the join.
        builder.end(with: .branch(conditionValue, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then, into: destination, borrowsPlaces: borrowsPlaces)
        builder.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise, into: destination, borrowsPlaces: borrowsPlaces)
        builder.end(with: .goto(join), continuingIn: join)
    }

    /// Lowers `branch`'s statements, then computes its value, where it gives one, into `destination`.
    private mutating func lower(_ branch: CheckedBranch, into destination: Destination?, borrowsPlaces: Bool) {
        lower(branch.statements)

        // A branch that gives no value computes none.
        guard let value = branch.value else { return }
        compute(value, into: destination, borrowsPlaces: borrowsPlaces)
    }

    /// Computes `expr`, an operation that is neither a place nor an `if`, into a new temporary that an operand reads,
    /// and returns the temporary's place.
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
        builder.emit(.operand(leftValue), into: result, range: range)

        // A `left` that decides goes on to the join, and any other to a block of its own that evaluates `right`.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)

        // There `right`'s value becomes the result, and both paths meet at the join, where lowering goes on.
        let rightValue = operand(of: right)
        builder.emit(.operand(rightValue), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}

private extension CheckedExpr {
    /// Whether the value is a place that its position borrows, or an `if` whose branches give such places, as the
    /// branches of a `ref let`'s value do.
    var borrowsPlaces: Bool {
        switch kind {
        case .place(_, .borrow): true
        case .if(_, let then, let otherwise): [then.value, otherwise.value].contains { $0?.borrowsPlaces == true }
        default: false
        }
    }
}

/// A call's argument once it is evaluated, before the call's accesses begin: what the call passes for it.
private enum EvaluatedArgument {
    /// A value the call passes as it is.
    case value(Operand)
    /// A place the call reaches through an access of the kind, which begins with the call's other accesses, and
    /// which the source names at the range.
    case place(Place, at: SourceRange, AccessKind)

    /// What the call passes for a borrowed argument whose value `operand` gives: a constant as it is, and the place
    /// any other value lies in, through a read access.
    static func borrowing(_ operand: Operand) -> EvaluatedArgument {
        guard case .read(let place, let range) = operand else { return .value(operand) }
        return .place(place, at: range, .read)
    }
}
