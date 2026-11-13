import RayoSema
import RayoSyntax

/// Lowers statements, the loops and jumps among them included.
extension FunctionLowering {
    mutating func lower(_ statements: [CheckedStmt]) {
        for statement in statements { lower(statement) }
    }

    private mutating func lower(_ statement: CheckedStmt) {
        switch statement {
        // An expression statement computes its value and drops it.
        case .expression(let expr):
            compute(expr, into: nil)

        // A declaration starts its local's life.
        case .binding(let place, let value):
            lowerDeclaration(of: place, givenBy: value)

        // An assignment computes its value into its place.
        case .assign(let place, let value):
            compute(value, into: Place(place))

        // A compound assignment applies its operator to its place and the value.
        case .compoundAssign(let place, let op, let value):
            lowerCompoundAssign(place, op, value)

        // A `while` loops through blocks of its own.
        case .whileStmt(let condition, let body):
            lowerWhile(condition, body)

        // A `break` goes to the innermost loop's exit.
        case .breakStmt:
            jump(with: .goto(innermostLoop.exit))

        // A `continue` goes back to the innermost loop's header.
        case .continueStmt:
            jump(with: .goto(innermostLoop.header))

        // A `return` leaves the function.
        case .returnStmt(let value):
            lowerReturn(value)
        }
    }

    /// Lowers `place op= value` as `place = place op value`.
    private mutating func lowerCompoundAssign(_ place: CheckedPlace, _ op: BinaryOperator, _ value: CheckedExpr) {
        let operand = operand(of: value)
        builder.emit(.binary(op, .read(Place(place)), operand), into: Place(place), range: place.range)
    }

    /// Starts the life of `place`'s local, and stores `value` in it when there is one.
    private mutating func lowerDeclaration(of place: CheckedPlace, givenBy value: CheckedExpr?) {
        builder.emit(.declare(place.local))

        // A local declared without a value holds none until it is assigned.
        guard let value else { return }
        compute(value, into: Place(place))
    }

    /// Leaves the function with `value`.
    private mutating func lowerReturn(_ value: CheckedExpr?) {
        let result = if let value { returnedOperand(of: value) } else { nil as Operand? }
        jump(with: .return(result))
    }

    /// Ends the current block with `terminator`, which jumps away from it, and goes on in a block of its own that no
    /// path reaches, where the code after the jump is lowered.
    private mutating func jump(with terminator: Terminator) {
        let unreached = builder.newBlock()
        builder.end(with: terminator, continuingIn: unreached)
    }

    /// The loop that a `break` or a `continue` belongs to, which the checker allows only inside one.
    private var innermostLoop: Loop {
        loops[loops.count - 1]
    }

    /// Lowers `value` to the operand a `return` leaves with, or, for a Void value, computes it for what it does
    /// and returns nil.
    private mutating func returnedOperand(of value: CheckedExpr) -> Operand? {
        // A value of any other type is the result.
        guard value.type == .void else { return operand(of: value) }
        compute(value, into: nil)
        return nil
    }

    private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
        // Make the loop's blocks: its header, its body, and its exit.
        let header = builder.newBlock()
        let bodyBlock = builder.newBlock()
        let exit = builder.newBlock()

        // Enter the loop at its header, which tests the condition and goes on to the body or the exit.
        builder.end(with: .goto(header), continuingIn: header)
        let test = headerTerminator(testing: condition, body: bodyBlock, exit: exit)
        builder.end(with: test, continuingIn: bodyBlock)

        // Lower the body with this loop innermost, so its `break` goes to `exit` and its `continue` to `header`.
        loops.append(Loop(header: header, exit: exit))
        lower(body)
        loops.removeLast()

        // The body's end goes back to the header, and lowering goes on after the loop.
        builder.end(with: .goto(header), continuingIn: exit)
    }

    /// Lowers `condition` into the current block, and returns the terminator that goes on from a loop's header to
    /// `body` when the condition holds and to `exit` when it doesn't.
    private mutating func headerTerminator(testing condition: CheckedExpr, body: BlockID, exit: BlockID) -> Terminator {
        // Only a `break` reaches the exit of a `while true`, so its header goes on to `body` alone.
        if case .boolLiteral(true) = condition.kind { return .goto(body) }
        return .branch(operand(of: condition), then: body, otherwise: exit)
    }
}

private extension Place {
    init(_ place: CheckedPlace) {
        self.init(local: place.local, fields: place.fields, range: place.range)
    }
}
