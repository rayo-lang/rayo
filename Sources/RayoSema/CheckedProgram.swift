import RayoSource
import RayoSyntax

/// The type of a value in a checked program.
public enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case bool
    case void

    public var description: String {
        switch self {
        case .int: return "Int"
        case .bool: return "Bool"
        case .void: return "Void"
        }
    }
}

/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    public var main: CheckedFunction
}

public struct CheckedFunction: Sendable {
    /// The function's locals, indexed by `LocalID`.
    public var locals: [CheckedLocal]
    public var body: [CheckedStmt]
}

/// Identifies a local of a function.
public struct LocalID: Hashable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}

public struct CheckedLocal: Sendable {
    public var name: String
    public var type: RayoType
    /// True for a `var`, which may be assigned after its declaration.
    public var isVar: Bool
}

/// A place that a statement writes, and where the source names it.
public struct CheckedPlace: Sendable {
    public var local: LocalID
    public var range: SourceRange
}

public enum CheckedStmt: Sendable {
    case expression(CheckedExpr)
    /// A declaration, which gives the new local its first value.
    case binding(LocalID, CheckedExpr)
    case assign(CheckedPlace, CheckedExpr)
    case compoundAssign(CheckedPlace, BinaryOperator, CheckedExpr)
    case ifStmt(condition: CheckedExpr, then: [CheckedStmt], otherwise: [CheckedStmt])
    case whileStmt(condition: CheckedExpr, body: [CheckedStmt])
    case breakStmt
    case continueStmt
}

public struct CheckedExpr: Sendable {
    public var kind: CheckedExprKind
    public var type: RayoType
    public var range: SourceRange
}

public indirect enum CheckedExprKind: Sendable {
    case intLiteral(Int64)
    case boolLiteral(Bool)
    case local(LocalID)
    case unary(UnaryOperator, CheckedExpr)
    case binary(BinaryOperator, CheckedExpr, CheckedExpr)
    case call(Callee, arguments: [CheckedExpr])
}

/// What a call calls.
public enum Callee: Hashable, Sendable {
    /// The prelude's `print(_: Int)`, which writes the integer and a newline to standard output.
    case printInt
}
