import RayoSource

public struct SourceFile: Sendable {
    public var functions: [FuncDecl]
    public init(functions: [FuncDecl]) { self.functions = functions }
}

/// `func name(parameters) -> Result { … }`, where the result type is optional.
public struct FuncDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    public var parameters: [Param]
    public var result: TypeExpr?
    public var body: Block
}

/// `label name: convention Type = default`, where all but the name and the type are optional.
public struct Param: Sendable {
    /// The label a call writes before the argument, or nil for `_`. A parameter declared without a label takes
    /// its name as its label, unless the name is `_`.
    public var label: String?
    public var name: String
    public var nameRange: SourceRange
    public var convention: ParamConvention?
    public var type: TypeExpr
    /// The value a call that leaves the argument out passes.
    public var defaultValue: Expr?
    public var range: SourceRange
}

/// How a parameter takes its argument, when it doesn't borrow it.
public enum ParamConvention: String, Sendable {
    case mutable, owned
}

public enum TypeExpr: Sendable {
    /// `Int`.
    case named(String, range: SourceRange)
    /// `()`.
    case void(range: SourceRange)

    public var range: SourceRange {
        switch self {
        case .named(_, let range), .void(let range):
            return range
        }
    }

    /// The type as the source writes it.
    public var spelling: String {
        switch self {
        case .named(let name, _): return name
        case .void: return "()"
        }
    }
}

public struct Block: Sendable {
    public var statements: [Stmt]
    /// The `}` that ends the block.
    public var closingBrace: SourceRange

    /// The block's one statement, when it is an expression.
    public var singleExpression: Expr? {
        guard statements.count == 1, case .expression(let expr) = statements[0].kind else { return nil }
        return expr
    }
}

public enum BindingKind: Sendable, Hashable {
    case `let`
    case `var`
}

public struct Binding: Sendable {
    public var kind: BindingKind
    public var name: String
    public var nameRange: SourceRange
    public var type: TypeExpr?
    public var value: Expr
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

public struct Stmt: Sendable {
    public var kind: StmtKind
    public var range: SourceRange
}

public indirect enum StmtKind: Sendable {
    case binding(Binding)
    case assign(target: Expr, op: AssignOperator, value: Expr)
    /// `_ = value`, which drops a value on purpose.
    case discard(Expr)
    case expression(Expr)
    case ifStmt(condition: Expr, then: Block, otherwise: Block?)
    case whileStmt(condition: Expr, body: Block)
    case breakStmt
    case continueStmt
    case returnStmt(Expr?)
}

public enum BinaryOperator: String, Sendable, Hashable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", remainder = "%"
    case equal = "==", notEqual = "!=", less = "<", lessEqual = "<=", greater = ">", greaterEqual = ">="
    case and = "&&", or = "||"
}

public enum UnaryOperator: String, Sendable, Hashable {
    case negate = "-"
    case not = "!"
}

public struct Expr: Sendable {
    public var kind: ExprKind
    public var range: SourceRange
}

/// `label: value`, or the value alone.
public struct Argument: Sendable {
    public var label: String?
    public var value: Expr
    /// The label, when there is one, and the value.
    public var range: SourceRange
}

public indirect enum ExprKind: Sendable {
    /// The literal's digits.
    case intLiteral(UInt64)
    /// `-digits`: a `-` with no operator between it and a literal, which is one literal with the negated
    /// value, so that `-9223372036854775808` is `Int.min` though `9223372036854775808` doesn't fit in an `Int`.
    case negativeIntLiteral(UInt64)
    case boolLiteral(Bool)
    case name(String)
    /// `name(arguments)`.
    case call(name: String, nameRange: SourceRange, arguments: [Argument])
    case unary(UnaryOperator, Expr)
    case binary(BinaryOperator, Expr, Expr)
    /// `copy name`: the value of a local, which the local keeps.
    case copy(name: String, nameRange: SourceRange)
}
