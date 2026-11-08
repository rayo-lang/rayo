import RayoSema
import RayoSyntax

/// Lowers a checked program to Rayo IR.
public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        IRProgram(main: lower(program.main))
    }

    static func lower(_ function: CheckedFunction) -> IRFunction {
        var builder = FunctionBuilder()
        for statement in function.body {
            switch statement {
            case .expression(let expr):
                builder.emit(builder.rvalue(of: expr), into: nil, range: expr.range)
            }
        }
        return IRFunction(locals: builder.locals,
                          blocks: [BasicBlock(statements: builder.statements, terminator: .return)])
    }
}

/// Builds one function's IR, giving each intermediate value a local of its own.
private struct FunctionBuilder {
    var locals: [RayoType] = []
    var statements: [Statement] = []

    mutating func emit(_ value: Rvalue, into destination: LocalID?, range: SourceRange) {
        statements.append(Statement(destination: destination, value: value, range: range))
    }

    mutating func rvalue(of expr: CheckedExpr) -> Rvalue {
        switch expr.kind {
        case .intLiteral(let value):
            return .use(.constant(value))
        case .unary(let op, let operand):
            return .unary(op, self.operand(of: operand))
        case .binary(let op, let left, let right):
            let left = operand(of: left)
            return .binary(op, left, operand(of: right))
        case .call(let callee, let arguments):
            return .call(callee, arguments: arguments.map { operand(of: $0) })
        }
    }

    /// An operand that holds `expr`'s value, computed into a new local unless it is a constant.
    mutating func operand(of expr: CheckedExpr) -> Operand {
        if case .intLiteral(let value) = expr.kind { return .constant(value) }
        let local = LocalID(index: locals.count)
        locals.append(expr.type)
        emit(rvalue(of: expr), into: local, range: expr.range)
        return .local(local)
    }
}
