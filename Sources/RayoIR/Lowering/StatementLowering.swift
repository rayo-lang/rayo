import RayoSema
import RayoSyntax

/// Lowers a function's statements into its control-flow graph, the branches and loops among them included.
struct StatementLowering {
    /// The blocks that a `continue` and a `break` in a loop's body go to.
    private struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    let graph: GraphBuilder
    private var loops: [Loop] = []

    init(graph: GraphBuilder) {
        self.graph = graph
    }

    private var expressions: ExpressionLowering { ExpressionLowering(graph: graph) }

    mutating func lower(_ statements: [CheckedStmt]) {
        for statement in statements { lower(statement) }
    }

    private mutating func lower(_ statement: CheckedStmt) {
        switch statement {
        // An expression statement computes its value and drops it.
        case .expression(let expr):
            graph.emit(expressions.rvalue(of: expr), into: nil, range: expr.range)

        // A declaration starts its local's life.
        case .binding(let place, let value):
            lowerDeclaration(of: place, givenBy: value)

        // An assignment computes its value into the local.
        case .assign(let place, let value):
            graph.emit(expressions.rvalue(of: value), into: Place(place), range: value.range)

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
            graph.end(with: .goto(loops[loops.count - 1].exit), continuingIn: graph.newBlock())

        // A `continue` goes back to the innermost loop's header, and the code after it to a block that no path
        // reaches.
        case .continueStmt:
            graph.end(with: .goto(loops[loops.count - 1].header), continuingIn: graph.newBlock())

        // A `return` leaves the function.
        case .returnStmt(let value):
            lowerReturn(value)
        }
    }

    /// Lowers `place op= value` as `place = place op value`.
    private func lowerCompoundAssign(_ place: CheckedPlace, _ op: BinaryOperator, _ value: CheckedExpr) {
        let value = expressions.operand(of: value)
        graph.emit(.binary(op, .read(Place(place)), value), into: Place(place), range: place.range)
    }

    /// Starts the life of `place`'s local, and stores `value` in it when there is one.
    private func lowerDeclaration(of place: CheckedPlace, givenBy value: CheckedExpr?) {
        graph.emit(.declare(place.local))
        // A local declared without a value holds none until it is assigned.
        guard let value else { return }
        graph.emit(expressions.rvalue(of: value), into: Place(place), range: value.range)
    }

    /// Leaves the function with `value`. A Void value is computed for what it does, and leaves with no result.
    private func lowerReturn(_ value: CheckedExpr?) {
        let result = value.flatMap { returnedOperand(of: $0) }
        // The code after the `return` goes in a block that no path reaches.
        graph.end(with: .return(result), continuingIn: graph.newBlock())
    }

    /// Lowers `value` to the operand a `return` leaves with, or, for a Void value, computes it for what it does
    /// and returns nil.
    private func returnedOperand(of value: CheckedExpr) -> Operand? {
        // A value of any other type is the result.
        guard value.type == .void else { return expressions.operand(of: value) }
        graph.emit(expressions.rvalue(of: value), into: nil, range: value.range)
        return nil
    }

    private mutating func lowerIf(_ condition: CheckedExpr, _ then: [CheckedStmt], _ otherwise: [CheckedStmt]) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let condition = expressions.operand(of: condition)
        let thenBlock = graph.newBlock()
        let elseBlock = graph.newBlock()
        let join = graph.newBlock()

        // Each branch runs its statements, then goes on to the join.
        graph.end(with: .branch(condition, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then)
        graph.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise)
        graph.end(with: .goto(join), continuingIn: join)
    }

    private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
        // Make the loop's blocks: its header, its body, and its exit.
        let header = graph.newBlock()
        let bodyBlock = graph.newBlock()
        let exit = graph.newBlock()

        // Enter the loop at its header, which tests the condition and goes on to the body or the exit.
        graph.end(with: .goto(header), continuingIn: header)
        graph.end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)

        // Lower the body with this loop innermost, so its `break` goes to `exit` and its `continue` to `header`.
        loops.append(Loop(header: header, exit: exit))
        lower(body)
        loops.removeLast()

        // The body's end goes back to the header, and lowering goes on after the loop.
        graph.end(with: .goto(header), continuingIn: exit)
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
