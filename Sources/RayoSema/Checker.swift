import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns the checked program when it has no errors.
    public static func check(_ file: SourceFile) -> (program: CheckedProgram?, diagnostics: [Diagnostic]) {
        var checker = FileChecker()
        let program = checker.check(file)
        let ordered = checker.diagnostics.enumerated().sorted { a, b in
            (a.element.range.start.offset, a.offset) < (b.element.range.start.offset, b.offset)
        }
        return (checker.diagnostics.isEmpty ? program : nil, ordered.map(\.element))
    }
}

/// What a call needs to know about the function it calls.
struct Signature {
    struct Parameter {
        var label: String?
        var type: RayoType
    }

    var name: String
    var parameters: [Parameter]
    var result: RayoType

    static let print = Signature(name: "print", parameters: [Parameter(label: nil, type: .int)], result: .void)
}

private struct FileChecker {
    /// The functions a program can name: the prelude's, and its own.
    static let functionNames: Set<String> = ["print", "main"]

    var diagnostics: [Diagnostic] = []

    mutating func check(_ file: SourceFile) -> CheckedProgram? {
        var main: FuncDecl?
        for declaration in file.declarations {
            switch declaration {
            case .structure(let structure):
                unsupported("a struct", at: structure.nameRange)
            case .function(let function) where function.name != "main":
                unsupported("a function other than 'main'", at: function.nameRange)
            case .function(let function) where main != nil:
                error("'main' is declared more than once", at: function.nameRange)
                _ = check(main: function)
            case .function(let function):
                main = function
            }
        }
        guard let main else {
            let start = SourceLocation(line: 1, column: 1, offset: 0)
            error("the program has no 'main' function", at: SourceRange(start, start))
            return nil
        }
        return CheckedProgram(main: check(main: main))
    }

    mutating func check(main: FuncDecl) -> CheckedFunction {
        checkSignature(ofMain: main)
        return CheckedFunction(body: main.body.statements.compactMap { check($0) })
    }

    mutating func checkSignature(ofMain main: FuncDecl) {
        if let parameter = main.params.first { error("'main' takes no parameters", at: parameter.range) }
        if let result = main.result, let type = resolve(result), type != .void {
            error("'main' returns Void, Never or Int32", at: result.range)
        }
    }

    mutating func resolve(_ type: TypeExpr) -> RayoType? {
        switch type {
        case .named("Int", let arguments, _) where arguments.isEmpty:
            return .int
        case .named("Void", let arguments, _) where arguments.isEmpty:
            return .void
        case .void:
            return .void
        default:
            unsupported("the type '\(type)'", at: type.range)
            return nil
        }
    }

    mutating func check(_ statement: Stmt) -> CheckedStmt? {
        switch statement.kind {
        case .expression(let expr):
            return check(expr).map { .expression($0) }
        case .binding(let binding):
            unsupported("a '\(binding.kind.rawValue)' declaration", at: statement.range)
        case .assign:
            unsupported("assignment", at: statement.range)
        case .ifStmt:
            unsupported("'if'", at: statement.range)
        case .whileStmt:
            unsupported("'while'", at: statement.range)
        case .forRange:
            unsupported("'for'", at: statement.range)
        case .returnStmt:
            unsupported("'return'", at: statement.range)
        case .breakStmt:
            unsupported("'break'", at: statement.range)
        case .continueStmt:
            unsupported("'continue'", at: statement.range)
        case .doBlock:
            unsupported("'do'", at: statement.range)
        }
        return nil
    }

    mutating func check(_ expr: Expr) -> CheckedExpr? {
        switch expr.kind {
        case .intLiteral(let digits):
            return literal(Int64(exactly: digits), in: expr.range)
        case .negativeIntLiteral(let digits):
            let value = digits == Int64.min.magnitude ? Int64.min : Int64(exactly: digits).map { -$0 }
            return literal(value, in: expr.range)
        case .unary(.negate, let operand):
            guard let operand = check(operand), expect(operand, .int) else { return nil }
            return CheckedExpr(kind: .unary(.negate, operand), type: .int, range: expr.range)
        case .binary(let op, let left, let right) where op.isArithmetic:
            return arithmetic(op, left, right, in: expr.range)
        case .call(let callee, let arguments):
            return call(callee, arguments, in: expr.range)
        case .name(let name, _) where Self.functionNames.contains(name):
            unsupported("using a function as a value", at: expr.range)
        case .name(let name, _):
            error("'\(name)' isn't declared", at: expr.range)
        case .unary(let op, _):
            unsupported("'\(op.rawValue)'", at: expr.range)
        case .binary(let op, _, _):
            unsupported("'\(op.rawValue)'", at: expr.range)
        default:
            unsupported(expr.kind.construct, at: expr.range)
        }
        return nil
    }

    mutating func arithmetic(_ op: BinaryOperator, _ left: Expr, _ right: Expr, in range: SourceRange) -> CheckedExpr? {
        let left = check(left)
        let right = check(right)
        guard let left, let right else { return nil }
        guard left.type == .int && right.type == .int else {
            error("'\(op.rawValue)' needs Int operands, found \(left.type) and \(right.type)", at: range)
            return nil
        }
        return CheckedExpr(kind: .binary(op, left, right), type: .int, range: range)
    }

    mutating func call(_ callee: Expr, _ arguments: [Argument], in range: SourceRange) -> CheckedExpr? {
        guard case .name(let name, let typeArguments) = callee.kind else {
            unsupported("calling \(callee.kind.construct)", at: callee.range)
            return nil
        }
        guard Self.functionNames.contains(name) else {
            error("'\(name)' isn't declared", at: callee.range)
            return nil
        }
        guard typeArguments.isEmpty else {
            error("'\(name)' takes no generic arguments", at: callee.range)
            return nil
        }
        guard name == "print" else {
            unsupported("calling 'main'", at: callee.range)
            return nil
        }
        let signature = Signature.print
        guard let checked = check(arguments, against: signature, in: range) else { return nil }
        return CheckedExpr(kind: .call(.printInt, arguments: checked), type: signature.result, range: range)
    }

    /// Checks `arguments` against `signature`'s parameters, one by one and in order. Every argument's value
    /// is checked, whether or not the call matches the signature.
    mutating func check(_ arguments: [Argument], against signature: Signature, in range: SourceRange) -> [CheckedExpr]? {
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let noun = parameters.count == 1 ? "argument" : "arguments"
            error("'\(signature.name)' takes \(parameters.count) \(noun), but the call passes \(arguments.count)",
                  at: range)
            arguments.forEach { _ = check($0.value) }
            return nil
        }
        var checked: [CheckedExpr] = []
        for (index, (argument, parameter)) in zip(arguments, parameters).enumerated() {
            let labelMatches = labelMatches(argument, parameter, position: index + 1, of: signature)
            if let value = check(argument.value), labelMatches, expect(value, parameter.type) {
                checked.append(value)
            }
        }
        return checked.count == arguments.count ? checked : nil
    }

    mutating func labelMatches(_ argument: Argument, _ parameter: Signature.Parameter, position: Int,
                               of signature: Signature) -> Bool {
        let argumentName = "argument \(position) of '\(signature.name)'"
        switch (parameter.label, argument.label) {
        case (nil, nil):
            return true
        case (let label?, let written?) where label == written:
            return true
        case (nil, let written?):
            error("\(argumentName) takes no label, not '\(written)'", at: argument.value.range)
        case (let label?, nil):
            error("\(argumentName) needs the label '\(label)'", at: argument.value.range)
        case (let label?, let written?):
            error("\(argumentName) takes the label '\(label)', not '\(written)'", at: argument.value.range)
        }
        return false
    }

    /// Whether `expr` has `type`, reporting it when it doesn't.
    mutating func expect(_ expr: CheckedExpr, _ type: RayoType) -> Bool {
        if expr.type == type { return true }
        error("expected \(type), found \(expr.type)", at: expr.range)
        return false
    }

    /// Checks an integer literal, whose `value` is nil when the literal doesn't fit in an `Int`.
    mutating func literal(_ value: Int64?, in range: SourceRange) -> CheckedExpr? {
        guard let value else {
            error("the literal doesn't fit in an Int", at: range)
            return nil
        }
        return CheckedExpr(kind: .intLiteral(value), type: .int, range: range)
    }

    mutating func error(_ message: String, at range: SourceRange) {
        diagnostics.append(.error(message, at: range))
    }

    mutating func unsupported(_ what: String, at range: SourceRange) {
        error("\(what) isn't supported yet", at: range)
    }
}

private extension ExprKind {
    /// What a message calls an expression of this kind.
    var construct: String {
        switch self {
        case .intLiteral, .negativeIntLiteral: return "an integer literal"
        case .boolLiteral: return "Bool"
        case .name: return "a name"
        case .selfRef: return "'self'"
        case .member: return "a member"
        case .index: return "indexing"
        case .call: return "a call"
        case .unary, .binary: return "an operator"
        case .lend: return "'&'"
        case .copy: return "'copy'"
        case .consume: return "'consume'"
        case .borrow: return "'borrow'"
        case .arrayLiteral: return "an array literal"
        case .closure: return "a closure"
        }
    }
}

private extension BinaryOperator {
    var isArithmetic: Bool {
        switch self {
        case .add, .subtract, .multiply, .divide, .remainder: return true
        default: return false
        }
    }
}
