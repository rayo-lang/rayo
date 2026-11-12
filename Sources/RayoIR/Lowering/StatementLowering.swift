import RayoSema
import RayoSyntax

/// Lowers statements into the function a builder builds, the loops and jumps among them included.
enum StatementLowering {
    static func lower(_ statements: [CheckedStmt], in builder: inout FunctionBuilder) {
        for statement in statements { lower(statement, in: &builder) }
    }

    private static func lower(_ statement: CheckedStmt, in builder: inout FunctionBuilder) {
        switch statement {
        // An expression statement computes its value and drops it.
        case .expression(let expr):
            ExpressionLowering.compute(expr, into: nil, in: &builder)

        // A declaration starts its local's life.
        case .binding(let place, let value):
            lowerDeclaration(of: place, givenBy: value, in: &builder)

        // An assignment computes its value into its place.
        case .assign(let place, let value):
            ExpressionLowering.compute(value, into: Place(place), in: &builder)

        // A compound assignment applies its operator to its place and the value.
        case .compoundAssign(let place, let op, let value):
            lowerCompoundAssign(place, op, value, in: &builder)

        // A `while` loops through blocks of its own.
        case .whileStmt(let condition, let body):
            lowerWhile(condition, body, in: &builder)

        // A `break` goes to the innermost loop's exit.
        case .breakStmt:
            jump(with: .goto(builder.innermostLoop.exit), in: &builder)

        // A `continue` goes back to the innermost loop's header.
        case .continueStmt:
            jump(with: .goto(builder.innermostLoop.header), in: &builder)

        // A `return` leaves the function.
        case .returnStmt(let value):
            lowerReturn(value, in: &builder)
        }
    }

    /// Lowers `place op= value` as `place = place op value`.
    private static func lowerCompoundAssign(_ place: CheckedPlace, _ op: BinaryOperator, _ value: CheckedExpr,
                                            in builder: inout FunctionBuilder) {
        let operand = ExpressionLowering.operand(of: value, in: &builder)
        builder.emit(.binary(op, .read(Place(place)), operand), into: Place(place), range: place.range)
    }

    /// Starts the life of `place`'s local, and stores `value` in it when there is one.
    private static func lowerDeclaration(of place: CheckedPlace, givenBy value: CheckedExpr?,
                                         in builder: inout FunctionBuilder) {
        builder.emit(.declare(place.local))

        // A local declared without a value holds none until it is assigned.
        guard let value else { return }
        ExpressionLowering.compute(value, into: Place(place), in: &builder)
    }

    /// Leaves the function with `value`.
    private static func lowerReturn(_ value: CheckedExpr?, in builder: inout FunctionBuilder) {
        let result = if let value { returnedOperand(of: value, in: &builder) } else { nil as Operand? }
        jump(with: .return(result), in: &builder)
    }

    /// Ends the current block with `terminator`, which jumps away from it, and goes on in a block of its own that no
    /// path reaches, where the code after the jump is lowered.
    private static func jump(with terminator: Terminator, in builder: inout FunctionBuilder) {
        let unreached = builder.newBlock()
        builder.end(with: terminator, continuingIn: unreached)
    }

    /// Lowers `value` to the operand a `return` leaves with, or, for a Void value, computes it for what it does
    /// and returns nil.
    private static func returnedOperand(of value: CheckedExpr, in builder: inout FunctionBuilder) -> Operand? {
        // A value of any other type is the result.
        guard value.type == .void else { return ExpressionLowering.operand(of: value, in: &builder) }
        ExpressionLowering.compute(value, into: nil, in: &builder)
        return nil
    }

    private static func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt], in builder: inout FunctionBuilder) {
        // Make the loop's blocks: its header, its body, and its exit.
        let header = builder.newBlock()
        let bodyBlock = builder.newBlock()
        let exit = builder.newBlock()

        // Enter the loop at its header, which tests the condition and goes on to the body or the exit.
        builder.end(with: .goto(header), continuingIn: header)
        let test = headerTerminator(testing: condition, body: bodyBlock, exit: exit, in: &builder)
        builder.end(with: test, continuingIn: bodyBlock)

        // Lower the body with this loop innermost, so its `break` goes to `exit` and its `continue` to `header`.
        builder.enterLoop(FunctionBuilder.Loop(header: header, exit: exit))
        lower(body, in: &builder)
        builder.leaveLoop()

        // The body's end goes back to the header, and lowering goes on after the loop.
        builder.end(with: .goto(header), continuingIn: exit)
    }

    /// Lowers `condition` into the current block, and returns the terminator that goes on from a loop's header to
    /// `body` when the condition holds and to `exit` when it doesn't.
    private static func headerTerminator(testing condition: CheckedExpr, body: BlockID, exit: BlockID,
                                         in builder: inout FunctionBuilder) -> Terminator {
        // Only a `break` reaches the exit of a `while true`, so its header goes on to `body` alone.
        if case .boolLiteral(true) = condition.kind { return .goto(body) }
        return .branch(ExpressionLowering.operand(of: condition, in: &builder), then: body, otherwise: exit)
    }
}

private extension Place {
    init(_ place: CheckedPlace) {
        self.init(local: place.local, fields: place.fields, range: place.range)
    }
}
