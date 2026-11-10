import RayoSema
import RayoSyntax

/// Lowers a function's statements into its control-flow graph, the branches and loops among them included.
struct StatementLowering {
    /// The blocks that a `continue` and a `break` in a loop's body go to.
    private struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    let builder: FunctionBuilder
    private let expressions: ExpressionLowering
    private var loops: [Loop] = []

    init(builder: FunctionBuilder) {
        self.builder = builder
        expressions = ExpressionLowering(builder: builder)
    }

    mutating func lower(_ statements: [CheckedStmt]) {
        for statement in statements { lower(statement) }
    }

    private mutating func lower(_ statement: CheckedStmt) {
        switch statement {
        // An expression statement computes its value and drops it.
        case .expression(let expr):
            builder.emit(expressions.rvalue(of: expr), into: nil, range: expr.range)

        // A declaration starts its local's life.
        case .binding(let place, let value):
            lowerDeclaration(of: place, givenBy: value)

        // An assignment computes its value into the local.
        case .assign(let place, let value):
            builder.emit(expressions.rvalue(of: value), into: Place(place), range: value.range)

        // A compound assignment applies its operator to the local and the value.
        case .compoundAssign(let place, let op, let value):
            lowerCompoundAssign(place, op, value)

        // An `if` branches between blocks of its own.
        case .ifStmt(let condition, let then, let otherwise):
            lowerIf(condition, then, otherwise)

        // A `while` loops through blocks of its own.
        case .whileStmt(let condition, let body):
            lowerWhile(condition, body)

        // A `break` goes to the innermost loop's exit, and the code after it to a block that no path reaches.
        case .breakStmt:
            builder.end(with: .goto(loops[loops.count - 1].exit), continuingIn: builder.newBlock())

        // A `continue` goes back to the innermost loop's header, and the code after it to a block that no path
        // reaches.
        case .continueStmt:
            builder.end(with: .goto(loops[loops.count - 1].header), continuingIn: builder.newBlock())

        // A `return` leaves the function.
        case .returnStmt(let value):
            lowerReturn(value)
        }
    }

    /// Lowers `place op= value` as `place = place op value`.
    private func lowerCompoundAssign(_ place: CheckedPlace, _ op: BinaryOperator, _ value: CheckedExpr) {
        let value = expressions.operand(of: value)
        builder.emit(.binary(op, .read(Place(place)), value), into: Place(place), range: place.range)
    }

    /// Starts the life of `place`'s local, and stores `value` in it when there is one.
    private func lowerDeclaration(of place: CheckedPlace, givenBy value: CheckedExpr?) {
        builder.emit(.declare(place.local))
        // A local declared without a value holds none until it is assigned.
        guard let value else { return }
        builder.emit(expressions.rvalue(of: value), into: Place(place), range: value.range)
    }

    /// Leaves the function with `value`.
    private func lowerReturn(_ value: CheckedExpr?) {
        let result = value.flatMap { returnedOperand(of: $0) }
        // The code after the `return` goes in a block that no path reaches.
        builder.end(with: .return(result), continuingIn: builder.newBlock())
    }

    /// Lowers `value` to the operand a `return` leaves with, or, for a Void value, computes it for what it does
    /// and returns nil.
    private func returnedOperand(of value: CheckedExpr) -> Operand? {
        // A value of any other type is the result.
        guard value.type == .void else { return expressions.operand(of: value) }
        builder.emit(expressions.rvalue(of: value), into: nil, range: value.range)
        return nil
    }

    private mutating func lowerIf(_ condition: CheckedExpr, _ then: [CheckedStmt], _ otherwise: [CheckedStmt]) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let condition = expressions.operand(of: condition)
        let thenBlock = builder.newBlock()
        let elseBlock = builder.newBlock()
        let join = builder.newBlock()

        // Each branch runs its statements, then goes on to the join.
        builder.end(with: .branch(condition, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then)
        builder.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise)
        builder.end(with: .goto(join), continuingIn: join)
    }

    private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
        // Make the loop's blocks: its header, its body, and its exit.
        let header = builder.newBlock()
        let bodyBlock = builder.newBlock()
        let exit = builder.newBlock()

        // Enter the loop at its header, which tests the condition and goes on to the body or the exit.
        builder.end(with: .goto(header), continuingIn: header)
        builder.end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)

        // Lower the body with this loop innermost, so its `break` goes to `exit` and its `continue` to `header`.
        loops.append(Loop(header: header, exit: exit))
        lower(body)
        loops.removeLast()

        // The body's end goes back to the header, and lowering goes on after the loop.
        builder.end(with: .goto(header), continuingIn: exit)
    }

    /// Lowers `condition` into the current block, and returns the terminator that goes on from a loop's header to
    /// `body` when the condition holds and to `exit` when it doesn't.
    private func headerTerminator(testing condition: CheckedExpr, body: BlockID, exit: BlockID) -> Terminator {
        // Only a `break` reaches the exit of a `while true`, so its header goes on to `body` alone.
        if case .boolLiteral(true) = condition.kind { return .goto(body) }
        return .branch(expressions.operand(of: condition), then: body, otherwise: exit)
    }
}

private extension Place {
    init(_ place: CheckedPlace) {
        self.init(local: place.local, range: place.range)
    }
}
