/// Identifies an expression within a file, as the key of per-expression side tables.
public struct ExprID: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var raw: Int
    public init(_ raw: Int) { self.raw = raw }
    public static func < (a: ExprID, b: ExprID) -> Bool { a.raw < b.raw }
    public var description: String { "e\(raw)" }
}

public struct SourceFile: Sendable {
    public var declarations: [Declaration]
    public init(declarations: [Declaration]) { self.declarations = declarations }
}

public enum Declaration: Sendable {
    case structure(StructDecl)
    case function(FuncDecl)
}

public struct Conformance: Sendable {
    /// `~Copyable` is written with `negated` set.
    public var negated: Bool
    public var name: String
    public var range: SourceRange
}

public struct StructDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    public var fields: [FieldDecl]
    public var conformances: [Conformance]
    public var methods: [FuncDecl]
    public var deinitBody: Block?
    public var range: SourceRange
}

/// A stored field, declared in the primary initializer: `struct Point(var x: Int, var y: Int = 0)`.
public struct FieldDecl: Sendable {
    public var isVar: Bool
    public var name: String
    /// Nil when the type comes from the default.
    public var type: TypeExpr?
    public var defaultValue: Expr?
    public var range: SourceRange
}

/// How a parameter receives its argument.
public enum ParamConvention: String, Sendable, Hashable {
    case borrowed
    case mutable
    case owned
}

/// How a method receives `self`: a plain `func` borrows it, a `mutating func` takes it `mutable`,
/// a `consuming func` `owned`.
public enum SelfConvention: String, Sendable, Hashable {
    case borrowed
    case mutating
    case consuming
}

public struct Param: Sendable {
    /// The argument label, or nil for `_`.
    public var label: String?
    public var name: String
    /// Nil when none is written, which means borrowed, except owned for a `mutating` or `consuming`
    /// function type or a `some F` of one.
    public var convention: ParamConvention?
    public var type: TypeExpr
    public var range: SourceRange
}

public struct FuncDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    /// Nil for a free function.
    public var selfConvention: SelfConvention?
    public var params: [Param]
    public var result: TypeExpr?
    public var body: Block
    public var range: SourceRange
}

/// What a closure does with its captures: reads them, writes them, or moves out of them.
public enum ClosureKind: String, Sendable, Hashable {
    case plain
    case mutating
    case consuming
}

/// A parameter of a function type: `keep StringView`, `mutable Particle`.
public struct FunctionTypeParam: Sendable {
    public var keep: Bool
    public var convention: ParamConvention?
    public var type: TypeExpr
}

public indirect enum TypeExpr: Sendable, CustomStringConvertible {
    /// `Int`, `Enemy`, `List<Int>`, `Closure<() -> Void>`.
    case named(String, arguments: [TypeExpr], range: SourceRange)
    /// `[N of T]`.
    case inlineArray(count: Int, element: TypeExpr, range: SourceRange)
    /// `()`.
    case void(range: SourceRange)
    /// `mutating (Int) -> Void`.
    case function(kind: ClosureKind, params: [FunctionTypeParam], result: TypeExpr, range: SourceRange)
    /// `some F`, for a function type `F`.
    case some(TypeExpr, range: SourceRange)

    public var range: SourceRange {
        switch self {
        case .named(_, _, let range), .inlineArray(_, _, let range), .void(let range), .function(_, _, _, let range),
             .some(_, let range):
            return range
        }
    }

    public var description: String {
        switch self {
        case .named(let name, let arguments, _):
            return arguments.isEmpty ? name : "\(name)<\(arguments.map(\.description).joined(separator: ", "))>"
        case .inlineArray(let count, let element, _):
            return "[\(count) of \(element)]"
        case .void:
            return "()"
        case .function(let kind, let params, let result, _):
            let list = params.map { param in
                var text = param.keep ? "keep " : ""
                if let convention = param.convention { text += "\(convention.rawValue) " }
                return text + param.type.description
            }
            let prefix = kind == .plain ? "" : "\(kind.rawValue) "
            return "\(prefix)(\(list.joined(separator: ", "))) -> \(result)"
        case .some(let constraint, _):
            return "some \(constraint)"
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
    public var owned: Bool
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

public enum CaptureMode: String, Sendable, Hashable {
    case move
    case copy
}

/// An entry of a closure's capture list: `[move level]`, `[copy id]`.
public struct Capture: Sendable {
    public var mode: CaptureMode
    /// `self` is written as the name `self`.
    public var name: String
    public var range: SourceRange
}

public struct ClosureParam: Sendable {
    public var name: String
    public var convention: ParamConvention?
    /// Nil when the closure lists names only, as in `{ a, b in … }`.
    public var type: TypeExpr?
    public var range: SourceRange
}

public struct ClosureExpr: Sendable {
    public var captures: [Capture]
    /// Nil when the closure has no parameter clause, so it takes its parameters from the expected type,
    /// and names them `$0`, `$1`, ….
    public var params: [ClosureParam]?
    public var result: TypeExpr?
    public var body: Block
}

public struct Expr: Sendable {
    public var id: ExprID
    public var kind: ExprKind
    public var range: SourceRange
}

public indirect enum ExprKind: Sendable {
    /// The literal's digits, before any `-` in front of it is applied.
    case intLiteral(UInt64)
    case boolLiteral(Bool)
    /// A name, with generic arguments where written: `x`, `List<Int>`.
    case name(String, typeArguments: [TypeExpr])
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
    case arrayLiteral([Expr])
    case closure(ClosureExpr)
}
