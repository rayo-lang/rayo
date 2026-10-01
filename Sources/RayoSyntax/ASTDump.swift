/// A compact, unambiguous text form of the syntax tree, which `rayoc parse` prints and the tests compare.
/// Operators and calls are prefix S-expressions, `(+ a b)` and `(call f a by:b)`, blocks are
/// `{s1; s2}`, and declarations keep the shape of their source.

extension SourceFile {
    public var dump: String { declarations.map(\.dump).joined(separator: "\n") }
}

extension Declaration {
    public var dump: String {
        switch self {
        case .structure(let decl): return decl.dump
        case .function(let decl): return decl.dump
        }
    }
}

extension StructDecl {
    public var dump: String {
        var text = "(struct \(name)"
        if !fields.isEmpty { text += "(\(fields.map(\.dump).joined(separator: ", ")))" }
        if !conformances.isEmpty {
            text += ": " + conformances.map { ($0.negated ? "~" : "") + $0.name }.joined(separator: ", ")
        }
        for method in methods { text += "\n  " + method.dump }
        if let deinitBody { text += "\n  (deinit \(deinitBody.dump))" }
        return text + ")"
    }
}

extension FieldDecl {
    public var dump: String {
        var text = "\(isVar ? "var" : "let") \(name)"
        if let type { text += ": \(type)" }
        if let defaultValue { text += " = \(defaultValue.dump)" }
        return text
    }
}

extension FuncDecl {
    public var dump: String {
        let prefix: String
        switch selfConvention {
        case .mutating: prefix = "mutating "
        case .consuming: prefix = "consuming "
        case .borrowed, nil: prefix = ""
        }
        var text = "(\(prefix)func \(name)(\(params.map(\.dump).joined(separator: ", ")))"
        if let result { text += " -> \(result)" }
        return text + " \(body.dump))"
    }
}

extension Param {
    public var dump: String {
        let names: String
        switch label {
        case nil: names = "_ \(name)"
        case name: names = name
        case let label?: names = "\(label) \(name)"
        }
        return "\(names): \(typeDump(convention, type))"
    }
}

private func typeDump(_ convention: ParamConvention?, _ type: TypeExpr) -> String {
    convention.map { "\($0.rawValue) \(type)" } ?? type.description
}

extension Block {
    public var dump: String { "{" + statements.map(\.dump).joined(separator: "; ") + "}" }
}

extension Stmt {
    public var dump: String {
        switch kind {
        case .binding(let binding):
            var text = "(\(binding.owned ? "owned " : "")\(binding.kind.rawValue) \(binding.name)"
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
        case .intLiteral(let value):
            return String(value)
        case .boolLiteral(let value):
            return String(value)
        case .name(let name, let typeArguments):
            return typeArguments.isEmpty ? name : "\(name)<\(typeArguments.map(\.description).joined(separator: ", "))>"
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
        case .arrayLiteral(let elements):
            return sExpression("array", elements.map(\.dump))
        case .closure(let closure):
            return closure.dump
        }
    }
}

private func sExpression(_ head: String, _ parts: [String]) -> String {
    "(" + ([head] + parts).joined(separator: " ") + ")"
}

extension ClosureExpr {
    public var dump: String {
        var parts = ["closure"]
        if !captures.isEmpty {
            parts.append("[" + captures.map { "\($0.mode.rawValue) \($0.name)" }.joined(separator: ", ") + "]")
        }
        if let params {
            let list = params.map { param in param.type.map { "\(param.name): \(typeDump(param.convention, $0))" } ?? param.name }
            parts.append("(" + list.joined(separator: ", ") + ")")
        }
        if let result { parts.append("-> \(result)") }
        parts.append(body.dump)
        return "(" + parts.joined(separator: " ") + ")"
    }
}
