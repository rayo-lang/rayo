import RayoSema
import RayoSource
import RayoSyntax

public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        IRProgram(functions: program.functions.map(lower), main: program.main)
    }

    static func lower(_ function: CheckedFunction) -> IRFunction {
        var builder = FunctionBuilder(locals: function.locals.map(IRLocal.init))
        builder.lower(function.body)
        // The checker has made every path of a function with a result end in a 'return'.
        builder.end(with: function.result == .void ? .return(nil) : .unreachable)
        return builder.function(lowering: function)
    }
}

/// Builds one function's control-flow graph, statement by statement, into the block that is current.
private struct FunctionBuilder {
    private struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    private var locals: [IRLocal]
    /// The blocks so far; a block has no terminator until lowering leaves it.
    private var blocks: [(statements: [Statement], terminator: Terminator?)] = [([], nil)]
    private var current = BlockID(index: 0)
    private var loops: [Loop] = []

    init(locals: [IRLocal]) {
        self.locals = locals
    }

    /// The IR function these blocks make of `checked`.
    func function(lowering checked: CheckedFunction) -> IRFunction {
        let blocks = blocks.map { block in
            guard let terminator = block.terminator else { preconditionFailure("a block was left unterminated") }
            return BasicBlock(statements: block.statements, terminator: terminator)
        }
        return IRFunction(name: checked.name, parameterCount: checked.parameterCount, result: checked.result,
                          locals: locals, blocks: blocks)
    }

    // MARK: Blocks

    private mutating func newBlock() -> BlockID {
        blocks.append(([], nil))
        return BlockID(index: blocks.count - 1)
    }

    mutating func end(with terminator: Terminator) {
        blocks[current.index].terminator = terminator
    }

    /// Ends the current block with `terminator`, and continues in `next`.
    private mutating func end(with terminator: Terminator, continuingIn next: BlockID) {
        end(with: terminator)
        current = next
    }

    private mutating func emit(_ value: Rvalue, into destination: Place?, range: SourceRange) {
        emit(.compute(destination: destination, value: value, range: range))
    }

    private mutating func emit(_ statement: Statement) {
        blocks[current.index].statements.append(statement)
    }

    // MARK: Statements

    mutating func lower(_ statements: [CheckedStmt]) {
        for statement in statements { lower(statement) }
    }

    private mutating func lower(_ statement: CheckedStmt) {
        switch statement {
        case .expression(let expr):
            emit(rvalue(of: expr), into: nil, range: expr.range)
        case .binding(let place, let value):
            lowerDeclaration(of: place, givenBy: value)
        case .assign(let place, let value):
            emit(rvalue(of: value), into: Place(place), range: value.range)
        case .compoundAssign(let place, let op, let value):
            lowerCompoundAssign(place, op, value)
        case .ifStmt(let condition, let then, let otherwise):
            lowerIf(condition, then, otherwise)
        case .whileStmt(let condition, let body):
            lowerWhile(condition, body)
        case .breakStmt:
            end(with: .goto(loops[loops.count - 1].exit), continuingIn: newBlock())
        case .continueStmt:
            end(with: .goto(loops[loops.count - 1].header), continuingIn: newBlock())
        case .returnStmt(let value):
            lowerReturn(value)
        }
    }

    /// Lowers `place op= value` as `place = place op value`.
    private mutating func lowerCompoundAssign(_ place: CheckedPlace, _ op: BinaryOperator, _ value: CheckedExpr) {
        let value = operand(of: value)
        emit(.binary(op, .read(Place(place)), value), into: Place(place), range: place.range)
    }

    /// Starts the life of `place`'s local, and stores `value` in it when there is one.
    private mutating func lowerDeclaration(of place: CheckedPlace, givenBy value: CheckedExpr?) {
        emit(.declare(place.local))
        guard let value else { return }
        emit(rvalue(of: value), into: Place(place), range: value.range)
    }

    /// Leaves the function with `value`. A Void value is computed for what it does, and leaves with no result.
    private mutating func lowerReturn(_ value: CheckedExpr?) {
        var result: Operand?
        if let value, value.type == .void {
            emit(rvalue(of: value), into: nil, range: value.range)
        } else if let value {
            result = operand(of: value)
        }
        end(with: .return(result), continuingIn: newBlock())
    }

    private mutating func lowerIf(_ condition: CheckedExpr, _ then: [CheckedStmt], _ otherwise: [CheckedStmt]) {
        let condition = operand(of: condition)
        let thenBlock = newBlock()
        let elseBlock = newBlock()
        let join = newBlock()
        end(with: .branch(condition, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then)
        end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise)
        end(with: .goto(join), continuingIn: join)
    }

    private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
        let header = newBlock()
        let bodyBlock = newBlock()
        let exit = newBlock()
        end(with: .goto(header), continuingIn: header)
        end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)
        loops.append(Loop(header: header, exit: exit))
        lower(body)
        loops.removeLast()
        end(with: .goto(header), continuingIn: exit)
    }

    /// Lowers `condition` into the current block, and returns the terminator that goes on from a loop's header to
    /// `body` when the condition holds and to `exit` when it doesn't. Only a `break` reaches the exit of a
    /// `while true`, so its header goes on to `body` alone.
    private mutating func headerTerminator(testing condition: CheckedExpr, body: BlockID,
                                           exit: BlockID) -> Terminator {
        if case .boolLiteral(true) = condition.kind { return .goto(body) }
        return .branch(operand(of: condition), then: body, otherwise: exit)
    }

    // MARK: Expressions

    private mutating func rvalue(of expr: CheckedExpr) -> Rvalue {
        switch expr.kind {
        case .intLiteral, .boolLiteral, .local, .move, .binary(.and, _, _), .binary(.or, _, _):
            return .use(operand(of: expr))
        case .unary(let op, let operand):
            return .unary(op, self.operand(of: operand))
        case .binary(let op, let left, let right):
            let left = operand(of: left)
            return .binary(op, left, operand(of: right))
        case .call(let callee, let arguments):
            return .call(callee, arguments: arguments.map { operand(of: $0) })
        }
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary unless it is a constant
    /// or a local.
    private mutating func operand(of expr: CheckedExpr) -> Operand {
        switch expr.kind {
        case .intLiteral(let value):
            return .constant(.int(value))
        case .boolLiteral(let value):
            return .constant(.bool(value))
        case .local(let local):
            return .read(Place(local: local, range: expr.range))
        case .move(let local):
            return .move(Place(local: local, range: expr.range))
        case .binary(.and, let left, let right):
            return shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range)
        case .binary(.or, let left, let right):
            return shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range)
        default:
            return lowerIntoTemporary(expr)
        }
    }

    /// Computes `expr` into a new temporary, and returns an operand that reads it.
    private mutating func lowerIntoTemporary(_ expr: CheckedExpr) -> Operand {
        let temporary = newTemporary(expr.type, at: expr.range)
        emit(rvalue(of: expr), into: temporary, range: expr.range)
        return .read(temporary)
    }

    /// Lowers `left && right` or `left || right` into branches, and returns an operand that holds the result: `left`
    /// when `left` is `decidingValue`, and otherwise `right`, which is evaluated only then.
    private mutating func shortCircuit(_ left: CheckedExpr, _ right: CheckedExpr, decidedWhenLeftIs decidingValue: Bool,
                                       range: SourceRange) -> Operand {
        let result = newTemporary(.bool, at: range)
        let resultValue = Operand.read(result)
        emit(.use(operand(of: left)), into: result, range: range)
        let evaluateRight = newBlock()
        let join = newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        end(with: branch, continuingIn: evaluateRight)
        emit(.use(operand(of: right)), into: result, range: range)
        end(with: .goto(join), continuingIn: join)
        return resultValue
    }

    /// Adds a temporary of `type` to the function, and returns its place, whose range is that of the expression it
    /// holds.
    private mutating func newTemporary(_ type: RayoType, at range: SourceRange) -> Place {
        locals.append(.temporary(type))
        return Place(local: LocalID(index: locals.count - 1), range: range)
    }
}

private extension Place {
    init(_ place: CheckedPlace) {
        self.init(local: place.local, range: place.range)
    }
}

private extension IRLocal {
    init(_ local: CheckedLocal) {
        self = .source(name: local.name, kind: local.kind, type: local.type)
    }
}
