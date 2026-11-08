/// A compact, unambiguous text form of the syntax tree, which `rayoc parse` prints and the tests compare.
/// Operators and calls are prefix S-expressions, `(+ a b)` and `(call f a b)`, blocks are
/// `{s1; s2}`, and declarations keep the shape of their source.

extension SourceFile {
    public var dump: String { functions.map(\.dump).joined(separator: "\n") }
}

extension FuncDecl {
    public var dump: String {
        var text = "(func \(name)()"
        if let result { text += " -> \(result)" }
        return text + " \(body.dump))"
    }
}

extension Block {
    public var dump: String { "{" + statements.map(\.dump).joined(separator: "; ") + "}" }
}

extension Stmt {
    public var dump: String {
        switch kind {
        case .binding(let binding):
            var text = "(\(binding.kind.rawValue) \(binding.name)"
            if let type = binding.type { text += ": \(type)" }
            return text + " \(binding.value.dump))"
        case .assign(let target, let op, let value):
            return "(\(op.rawValue) \(target.dump) \(value.dump))"
        case .expression(let expr):
            return expr.dump
        case .ifStmt(let condition, let then, let otherwise):
            let elsePart = otherwise.map { " else \($0.dump)" } ?? ""
            return "(if \(condition.dump) \(then.dump)\(elsePart))"
        case .whileStmt(let condition, let body):
            return "(while \(condition.dump) \(body.dump))"
        case .breakStmt:
            return "(break)"
        case .continueStmt:
            return "(continue)"
        }
    }
}

extension Expr {
    public var dump: String {
        switch kind {
        case .negativeIntLiteral(let digits):
            return "-\(digits)"
        case .intLiteral(let value):
            return String(value)
        case .boolLiteral(let value):
            return String(value)
        case .name(let name):
            return name
        case .call(let name, _, let arguments):
            return "(" + (["call", name] + arguments.map(\.dump)).joined(separator: " ") + ")"
        case .unary(let op, let operand):
            return "(\(op.rawValue) \(operand.dump))"
        case .binary(let op, let left, let right):
            return "(\(op.rawValue) \(left.dump) \(right.dump))"
        case .copy(let name, _):
            return "(copy \(name))"
        }
    }
}
