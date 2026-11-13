internal import RayoDiagnostics

/// Parses blocks and the statements in them.
extension Parser {
    mutating func parseBlock() throws(ParseFailure) -> Block {
        try expect(.lbrace, else: ErrorCode.missingBlock)
        let statements = parseStatements()
        let closingBrace = try expect(.rbrace, else: ErrorCode.unclosedBlock).range
        return Block(statements: statements, closingBrace: closingBrace)
    }

    private mutating func parseStatements() -> [Stmt] {
        parseLines(ifUnended: ErrorCode.unendedStatement) { parser throws(ParseFailure) in
            try parser.parseStatement()
        }
    }

    private mutating func parseStatement() throws(ParseFailure) -> Stmt {
        let start = current.range
        let kind: StmtKind = if consume(.let) {
            // A `let` declares the bindings after it, which never change.
            .declaration(.let, try parseBindings())
        } else if consume(.var) {
            // A `var` declares the bindings after it, which can.
            .declaration(.var, try parseBindings())
        } else if consume(.if) {
            // An `if` takes a condition, a block, and maybe an `else`.
            .ifStmt(try parseIf())
        } else if consume(.while) {
            // A `while` takes a condition and the loop's body.
            .whileStmt(condition: try parseExpression(), body: try parseBlock())
        } else if consume(.break) {
            // A `break` is the whole statement.
            .breakStmt
        } else if consume(.continue) {
            // So is a `continue`.
            .continueStmt
        } else if consume(.return) {
            // A `return` takes a value, unless its statement ends right after it.
            .returnStmt(atStatementEnd ? nil : try parseExpression())
        } else if consumeDrop() {
            // `_ =` drops the value after it.
            .drop(try parseExpression())
        } else {
            // A statement that starts with none of these is an expression, or an assignment to one.
            try parseExpressionStatement()
        }
        return Stmt(kind: kind, range: range(from: start))
    }

    /// Consumes `_ =`, which starts a statement that drops a value, when it comes next.
    private mutating func consumeDrop() -> Bool {
        // Anything but `_ =` starts some other statement.
        guard current.kind == .identifier("_"), peek().isPunct(.assign) else { return false }
        advance()
        advance()
        return true
    }

    /// An expression, or an assignment to one.
    private mutating func parseExpressionStatement() throws(ParseFailure) -> StmtKind {
        let target = try parseExpression()
        // An expression that no assignment operator follows is the whole statement.
        guard case .punct(let punct) = current.kind, let op = punct.assignOperator else {
            return .expression(target)
        }
        advance()
        return .assign(target: target, op: op, value: try parseExpression())
    }

    /// After the `let` or `var`: `binding (',' binding)*`.
    private mutating func parseBindings() throws(ParseFailure) -> [Binding] {
        var bindings = [try parseBinding()]
        while consume(.comma) { bindings.append(try parseBinding()) }
        return bindings
    }

    /// `identifier (':' type)? ('=' expression)?`.
    private mutating func parseBinding() throws(ParseFailure) -> Binding {
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingBindingName)
        let type = consume(.colon) ? try parseType() : nil
        let value = consume(.assign) ? try parseExpression() : nil
        return Binding(name: name, nameRange: nameRange, type: type, value: value)
    }
}
