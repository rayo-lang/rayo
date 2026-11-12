import RayoSema
import RayoSource

/// Lowers expressions into the function a builder builds, from its current block on, as the operations that compute
/// them and the operands that hold their values.
enum ExpressionLowering {
    /// Lowers `expr` into `builder`, as the computation of its value into `destination`, or, where `destination` is
    /// nil, of a value that is dropped.
    static func compute(_ expr: CheckedExpr, into destination: Place?, in builder: inout FunctionBuilder) {
        // An `if` whose value is dropped runs the branch its condition picks, and computes that branch's value for
        // what it does, so a Void `if` needs no temporary.
        if destination == nil, case .if(let condition, let then, let otherwise) = expr.kind {
            return lowerIf(condition, then, otherwise, into: nil, in: &builder)
        }

        // Any other value is one operation, whose operands are computed first.
        let value = rvalue(of: expr, in: &builder)
        builder.emit(value, into: destination, range: expr.range)
    }

    /// Lowers `expr` to an operand that holds its value, computing it into a new temporary of `builder` unless it is
    /// a constant, a local or a field of one.
    static func operand(of expr: CheckedExpr, in builder: inout FunctionBuilder) -> Operand {
        switch expr.kind {
        // An integer is a constant operand.
        case .intLiteral(let value): .constant(.int(value))
        // So is a Bool.
        case .boolLiteral(let value): .constant(.bool(value))
        // A local that the checker reads is read, keeping its value.
        case .local(let local): .read(Place(local: local, range: expr.range))
        // A local, or a field, that the checker moves gives its value up.
        case .move(let moved): .move(place(of: moved, in: &builder))
        // `&&` evaluates its right operand only when its left one is true.
        case .binary(.and, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: false, range: expr.range, in: &builder)
        // `||` evaluates its right operand only when its left one is false.
        case .binary(.or, let left, let right):
            shortCircuit(left, right, decidedWhenLeftIs: true, range: expr.range, in: &builder)
        // A field is read where it lies, in its struct's place, and an `if` from the temporary its branches compute.
        case .field, .if:
            .read(place(of: expr, in: &builder))
        // Any other operation, a call, and a struct's value, is computed into a temporary.
        case .unary, .binary, .call, .structure:
            .read(lowerIntoTemporary(expr, in: &builder))
        }
    }

    /// Lowers `expr` to the place that holds its value: a local, a field inside the place of its struct, or else a
    /// new temporary of `builder` that `expr`, or each branch of an `if`, is computed into.
    private static func place(of expr: CheckedExpr, in builder: inout FunctionBuilder) -> Place {
        switch expr.kind {
        // A local that the checker reads is its own place.
        case .local(let local):
            Place(local: local, range: expr.range)

        // A field lies inside the place of the struct that holds it.
        case .field(let structure, let index):
            place(of: structure, in: &builder).appending(field: index, at: expr.range)

        // An `if` holds its value in a temporary, which the branch that runs computes it into, on that branch's path.
        case .if(let condition, let then, let otherwise):
            lowerIf(condition, then, otherwise, intoTemporaryOf: expr.type, at: expr.range, in: &builder)

        // Any other value is held in a temporary.
        default:
            lowerIntoTemporary(expr, in: &builder)
        }
    }

    /// Lowers `expr` to the operation that computes its value, computing its operands into `builder` first.
    private static func rvalue(of expr: CheckedExpr, in builder: inout FunctionBuilder) -> Rvalue {
        switch expr.kind {
        // A constant, a local or a field is an operand as it is, and so is `&&`, `||` or an `if`, which lowers to
        // branches.
        case .intLiteral, .boolLiteral, .local, .move, .field, .binary(.and, _, _), .binary(.or, _, _), .if:
            .use(operand(of: expr, in: &builder))
        // A unary operation applies to its operand, computed first.
        case .unary(let op, let value):
            .unary(op, operand(of: value, in: &builder))
        // The left operand is computed before the right one, in the order the source reads.
        case .binary(let op, let left, let right):
            .binary(op, operand(of: left, in: &builder), operand(of: right, in: &builder))
        // So are the arguments of a call, from first to last.
        case .call(let callee, let arguments):
            .call(callee, arguments: arguments.map { operand(of: $0, in: &builder) })
        // And the values of a struct's fields, in the order the struct declares them.
        case .structure(let id, let fields):
            .structure(id, fields: fields.map { operand(of: $0, in: &builder) })
        }
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into a new
    /// temporary of `type` at `range`, and returns the temporary's place.
    private static func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                intoTemporaryOf type: RayoType, at range: SourceRange,
                                in builder: inout FunctionBuilder) -> Place {
        let temporary = builder.newTemporary(type, at: range)
        lowerIf(condition, then, otherwise, into: temporary, in: &builder)
        return temporary
    }

    /// Lowers `condition` and the branches it chooses between, computing the value of the branch that runs into
    /// `destination`, or dropping it where `destination` is nil.
    private static func lowerIf(_ condition: CheckedExpr, _ then: CheckedBranch, _ otherwise: CheckedBranch,
                                into destination: Place?, in builder: inout FunctionBuilder) {
        // Compute the condition, and make the blocks of the two branches and of the join after them.
        let conditionValue = operand(of: condition, in: &builder)
        let thenBlock = builder.newBlock()
        let elseBlock = builder.newBlock()
        let join = builder.newBlock()

        // Each branch runs its statements and computes its value, then goes on to the join.
        builder.end(with: .branch(conditionValue, then: thenBlock, otherwise: elseBlock), continuingIn: thenBlock)
        lower(then, into: destination, in: &builder)
        builder.end(with: .goto(join), continuingIn: elseBlock)
        lower(otherwise, into: destination, in: &builder)
        builder.end(with: .goto(join), continuingIn: join)
    }

    /// Lowers `branch`'s statements, then computes its value, where it gives one, into `destination`.
    private static func lower(_ branch: CheckedBranch, into destination: Place?, in builder: inout FunctionBuilder) {
        StatementLowering.lower(branch.statements, in: &builder)

        // A branch that gives no value computes none.
        guard let value = branch.value else { return }
        compute(value, into: destination, in: &builder)
    }

    /// Computes `expr` into a new temporary of `builder`, and returns the temporary's place.
    private static func lowerIntoTemporary(_ expr: CheckedExpr, in builder: inout FunctionBuilder) -> Place {
        let temporary = builder.newTemporary(expr.type, at: expr.range)
        compute(expr, into: temporary, in: &builder)
        return temporary
    }

    /// Lowers `left && right` or `left || right` into branches, and returns an operand that holds the result: `left`
    /// when `left` is `decidingValue`, and otherwise `right`, which is evaluated only then.
    private static func shortCircuit(
        _ left: CheckedExpr, _ right: CheckedExpr, decidedWhenLeftIs decidingValue: Bool, range: SourceRange,
        in builder: inout FunctionBuilder,
    ) -> Operand {
        // The result starts as `left`'s value, which is the result when it is `decidingValue`.
        let result = builder.newTemporary(.bool, at: range)
        let resultValue = Operand.read(result)
        let leftValue = operand(of: left, in: &builder)
        builder.emit(.use(leftValue), into: result, range: range)

        // A `left` that decides goes on to the join, and any other to a block of its own that evaluates `right`.
        let evaluateRight = builder.newBlock()
        let join = builder.newBlock()
        let branch: Terminator = decidingValue
            ? .branch(resultValue, then: join, otherwise: evaluateRight)
            : .branch(resultValue, then: evaluateRight, otherwise: join)
        builder.end(with: branch, continuingIn: evaluateRight)

        // There `right`'s value becomes the result, and both paths meet at the join, where lowering goes on.
        let rightValue = operand(of: right, in: &builder)
        builder.emit(.use(rightValue), into: result, range: range)
        builder.end(with: .goto(join), continuingIn: join)
        return resultValue
    }
}
