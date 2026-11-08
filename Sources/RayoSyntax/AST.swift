import RayoSource

/// Identifies an expression within a file, as the key of per-expression side tables.
public struct ExprID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public static func < (a: ExprID, b: ExprID) -> Bool { a.raw < b.raw }
    public var description: String { "e\(raw)" }
}

public struct SourceFile: Sendable {
    public var functions: [FuncDecl]
    public init(functions: [FuncDecl]) { self.functions = functions }
}

/// `func name() -> Result { … }`, where the result type is optional.
public struct FuncDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    public var result: TypeExpr?
    public var body: Block
    public var range: SourceRange
}

public enum TypeExpr: Sendable, CustomStringConvertible {
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

    public var description: String {
        switch self {
        case .named(let name, _):
            return name
        case .void:
            return "()"
        }
    }
}

public struct Block: Sendable {
    public var statements: [Stmt]
    public var range: SourceRange
}

public enum BindingKind: String, Sendable, Hashable {
    case `let`
    case `var`
}

public struct Binding: Sendable {
    public var kind: BindingKind
    public var name: String
    public var nameRange: SourceRange
    public var type: TypeExpr?
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

public struct Stmt: Sendable {
    public var kind: StmtKind
    public var range: SourceRange
}

public indirect enum StmtKind: Sendable {
    case binding(Binding)
    case assign(target: Expr, op: AssignOperator, value: Expr)
    case expression(Expr)
    case ifStmt(condition: Expr, then: Block, otherwise: Block?)
    case whileStmt(condition: Expr, body: Block)
    /// `for name in lower..<upper { … }`.
    case forRange(name: String, nameRange: SourceRange, lower: Expr, upper: Expr, body: Block)
    case returnStmt(Expr?)
    case breakStmt
    case continueStmt
    /// `do { … }`: a block that groups statements.
    case doBlock(Block)
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

public struct Argument: Sendable {
    public var label: String?
    public var value: Expr
}

public struct Expr: Sendable {
    public var id: ExprID
    public var kind: ExprKind
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
    case selfRef
    case member(Expr, name: String, nameRange: SourceRange)
    case index(Expr, arguments: [Argument])
    case call(callee: Expr, arguments: [Argument])
    case unary(UnaryOperator, Expr)
    case binary(BinaryOperator, Expr, Expr)
    /// `&place`: a place lent for change.
    case lend(Expr)
    case copy(Expr)
    case consume(Expr)
    /// `borrow place`: a `let`'s initializer that borrows the place instead of moving out of it.
    case borrow(Expr)
    case arrayLiteral([Expr])
}
