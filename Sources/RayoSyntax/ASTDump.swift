/// A compact, unambiguous text form of the syntax tree, which `rayoc parse` prints and the tests compare.
/// Operators and calls are prefix S-expressions, `(+ a b)` and `(call f a by:b)`, blocks are
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
            if let value = binding.value { text += " \(value.dump)" }
            return text + ")"
        case .assign(let target, let op, let value):
            return "(\(op.rawValue) \(target.dump) \(value.dump))"
        case .expression(let expr):
            return expr.dump
        case .ifStmt(let condition, let then, let otherwise):
            let elsePart = otherwise.map { " else \($0.dump)" } ?? ""
            return "(if \(condition.dump) \(then.dump)\(elsePart))"
        case .whileStmt(let condition, let body):
            return "(while \(condition.dump) \(body.dump))"
        case .forRange(let name, _, let lower, let upper, let body):
            return "(for \(name) \(lower.dump) \(upper.dump) \(body.dump))"
        case .returnStmt(let value):
            return value.map { "(return \($0.dump))" } ?? "(return)"
        case .breakStmt:
            return "(break)"
        case .continueStmt:
            return "(continue)"
        case .doBlock(let block):
            return "(do \(block.dump))"
        }
    }
}

extension Argument {
    public var dump: String { (label.map { "\($0):" } ?? "") + value.dump }
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
        case .selfRef:
            return "self"
        case .member(let base, let name, _):
            return "(. \(base.dump) \(name))"
        case .index(let base, let arguments):
            return sExpression("index", [base.dump] + arguments.map(\.dump))
        case .call(let callee, let arguments):
            return sExpression("call", [callee.dump] + arguments.map(\.dump))
        case .unary(let op, let operand):
            return "(\(op.rawValue) \(operand.dump))"
        case .binary(let op, let left, let right):
            return "(\(op.rawValue) \(left.dump) \(right.dump))"
        case .lend(let place):
            return "(& \(place.dump))"
        case .copy(let operand):
            return "(copy \(operand.dump))"
        case .consume(let operand):
            return "(consume \(operand.dump))"
        case .borrow(let operand):
            return "(borrow \(operand.dump))"
        case .arrayLiteral(let elements):
            return sExpression("array", elements.map(\.dump))
        }
    }
}

private func sExpression(_ head: String, _ parts: [String]) -> String {
    "(" + ([head] + parts).joined(separator: " ") + ")"
}
