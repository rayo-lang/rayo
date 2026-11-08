import RayoSyntax

/// The type of a value in a checked program.
public enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case void

    public var description: String {
        switch self {
        case .int: return "Int"
        case .void: return "Void"
        }
    }
}

/// A program that type-checked: every name is resolved, and every expression has its type.
public struct CheckedProgram: Sendable {
    public var main: CheckedFunction
}

public struct CheckedFunction: Sendable {
    public var body: [CheckedStmt]
}

public enum CheckedStmt: Sendable {
    case expression(CheckedExpr)
}

public struct CheckedExpr: Sendable {
    public var kind: CheckedExprKind
    public var type: RayoType
    public var range: SourceRange
}

public indirect enum CheckedExprKind: Sendable {
    case intLiteral(Int64)
    case unary(UnaryOperator, CheckedExpr)
    case binary(BinaryOperator, CheckedExpr, CheckedExpr)
    case call(Callee, arguments: [CheckedExpr])
}

/// What a call calls.
public enum Callee: Hashable, Sendable {
    /// The prelude's `print(_: Int)`, which writes the integer and a newline to standard output.
    case printInt
}
