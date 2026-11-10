import RayoSource

public struct Block: Sendable {
    public var statements: [Stmt]
    /// The `}` that ends the block.
    public var closingBrace: SourceRange

    /// The block's one statement, when it is an expression.
    public var singleExpression: Expr? {
        // A block of several statements, or of one that isn't an expression, has none.
        guard statements.count == 1, case .expression(let expr) = statements[0].kind else { return nil }
        return expr
    }
}

public struct Stmt: Sendable {
    public var kind: StmtKind
    public var range: SourceRange
}

public indirect enum StmtKind: Sendable {
    /// `let` or `var` and its bindings, separated by commas.
    case declaration(BindingKind, [Binding])
    case assign(target: Expr, op: AssignOperator, value: Expr)
    /// `_ = value`, which drops a value on purpose.
    case drop(Expr)
    case expression(Expr)
    case ifStmt(condition: Expr, then: Block, otherwise: Block?)
    case whileStmt(condition: Expr, body: Block)
    case breakStmt
    case continueStmt
    case returnStmt(Expr?)
}

/// `name: Type = value`, where the type and the value are optional.
public struct Binding: Sendable {
    public var name: String
    public var nameRange: SourceRange
    public var type: TypeExpr?
    /// The local's first value, or nil when the local holds none until it is assigned.
    public var value: Expr?
}

public enum AssignOperator: String, Sendable, Hashable {
    case assign = "="
    case add = "+="
    case subtract = "-="
    case multiply = "*="
    case divide = "/="
    case remainder = "%="

    /// The binary operator a compound assignment applies.
    public var binary: BinaryOperator? {
        switch self {
        case .assign: return nil
        case .add: return .add
        case .subtract: return .subtract
        case .multiply: return .multiply
        case .divide: return .divide
        case .remainder: return .remainder
        }
    }
}
