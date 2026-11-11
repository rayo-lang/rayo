import RayoDiagnostics

/// Parses blocks and the statements in them.
extension Parser {
    func parseBlock() throws(ParseFailure) -> Block {
        try expect(.lbrace, else: ErrorCode.missingBlock)
        let statements = parseStatements()
        let closingBrace = try expect(.rbrace, else: ErrorCode.unclosedBlock).range
        return Block(statements: statements, closingBrace: closingBrace)
    }

    private func parseStatements() -> [Stmt] {
        parseLines(ifUnended: ErrorCode.unendedStatement) { () throws(ParseFailure) in try parseStatement() }
    }

    private func parseStatement() throws(ParseFailure) -> Stmt {
        let start = current.range
        let kind: StmtKind
        // A `let` declares the bindings after it, which never change.
        if consume(.let) {
            kind = .declaration(.let, try parseBindings())
        } else if consume(.var) {
            // A `var` declares the bindings after it, which can.
            kind = .declaration(.var, try parseBindings())
        } else if consume(.if) {
            // An `if` takes a condition, a block, and maybe an `else`.
            kind = try parseIf()
        } else if consume(.while) {
            // A `while` takes a condition and the loop's body.
            let condition = try parseExpression()
            kind = .whileStmt(condition: condition, body: try parseBlock())
        } else if consume(.break) {
            // A `break` is the whole statement.
            kind = .breakStmt
        } else if consume(.continue) {
            // So is a `continue`.
            kind = .continueStmt
        } else if consume(.return) {
            // A `return` takes a value, unless its statement ends right after it.
            kind = .returnStmt(atStatementEnd ? nil : try parseExpression())
        } else if consumeDrop() {
            // `_ =` drops the value after it.
            kind = .drop(try parseExpression())
        } else {
            // A statement that starts with none of these is an expression, or an assignment to one.
            kind = try parseExpressionStatement()
        }
        return Stmt(kind: kind, range: range(from: start))
    }

    /// Consumes `_ =`, which starts a statement that drops a value, when it comes next.
    private func consumeDrop() -> Bool {
        // Anything but `_ =` starts some other statement.
        guard current.kind == .identifier("_"), peek().isPunct(.assign) else { return false }
        advance()
        advance()
        return true
    }

    /// An expression, or an assignment to one.
    private func parseExpressionStatement() throws(ParseFailure) -> StmtKind {
        let target = try parseExpression()
        // An expression that no assignment operator follows is the whole statement.
        guard case .punct(let punct) = current.kind, let op = punct.assignOperator else {
            return .expression(target)
        }
        advance()
        return .assign(target: target, op: op, value: try parseExpression())
    }

    /// After the `if`: the condition, the block, and the `else` part, when there is one.
    private func parseIf() throws(ParseFailure) -> StmtKind {
        let condition = try parseExpression()
        let then = try parseBlock()
        let otherwise = consume(.else) ? try parseElse() : nil
        return .ifStmt(condition: condition, then: then, otherwise: otherwise)
    }

    /// After the `else`: a block, or an `if` that is the one statement of the block it stands for.
    private func parseElse() throws(ParseFailure) -> Block {
        // An `else` without an `if` after it takes a block of its own.
        guard current.isKeyword(.if) else { return try parseBlock() }
        let start = advance().range
        let nested = Stmt(kind: try parseIf(), range: range(from: start))
        // The nested `if` ends with the `}` of its last block, which ends this one too.
        return Block(statements: [nested], closingBrace: previousRange)
    }

    /// After the `let` or `var`: `binding (',' binding)*`.
    private func parseBindings() throws(ParseFailure) -> [Binding] {
        var bindings = [try parseBinding()]
        while consume(.comma) { bindings.append(try parseBinding()) }
        return bindings
    }

    /// `identifier (':' type)? ('=' expression)?`.
    private func parseBinding() throws(ParseFailure) -> Binding {
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingBindingName)
        let type = consume(.colon) ? try parseType() : nil
        let value = consume(.assign) ? try parseExpression() : nil
        return Binding(name: name, nameRange: nameRange, type: type, value: value)
    }
}
