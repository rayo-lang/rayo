import RayoDiagnostics

/// Parses blocks and the statements in them.
struct StatementParser {
    let tokens: TokenStream

    func parseBlock() throws(ParseFailure) -> Block {
        try tokens.expect(.lbrace, else: ErrorCode.missingBlock)
        let statements = parseStatements()
        let closingBrace = try tokens.expect(.rbrace, else: ErrorCode.unclosedBlock).range
        return Block(statements: statements, closingBrace: closingBrace)
    }

    private func parseStatements() -> [Stmt] {
        SequenceParser(tokens: tokens).parseSequence(ifUnended: ErrorCode.unendedStatement) {
            () throws(ParseFailure) in try parseStatement()
        }
    }

    private func parseStatement() throws(ParseFailure) -> Stmt {
        let start = tokens.current.range
        let kind: StmtKind
        // A `let` declares the bindings after it, which never change.
        if tokens.consume(.let) {
            kind = .declaration(.let, try parseBindings())
        } else if tokens.consume(.var) {
            // A `var` declares the bindings after it, which can.
            kind = .declaration(.var, try parseBindings())
        } else if tokens.consume(.if) {
            // An `if` takes a condition, a block, and maybe an `else`.
            kind = try parseIf()
        } else if tokens.consume(.while) {
            // A `while` takes a condition and the loop's body.
            let condition = try ExpressionParser(tokens: tokens).parseExpression()
            kind = .whileStmt(condition: condition, body: try parseBlock())
        } else if tokens.consume(.break) {
            // A `break` is the whole statement.
            kind = .breakStmt
        } else if tokens.consume(.continue) {
            // So is a `continue`.
            kind = .continueStmt
        } else if tokens.consume(.return) {
            // A `return` takes a value, unless its statement ends right after it.
            kind = .returnStmt(tokens.atStatementEnd ? nil : try ExpressionParser(tokens: tokens).parseExpression())
        } else if consumeDrop() {
            // `_ =` drops the value after it.
            kind = .drop(try ExpressionParser(tokens: tokens).parseExpression())
        } else {
            // A statement that starts with none of these is an expression, or an assignment to one.
            kind = try parseExpressionStatement()
        }
        return Stmt(kind: kind, range: tokens.range(from: start))
    }

    /// Consumes `_ =`, which starts a statement that drops a value, when it comes next.
    private func consumeDrop() -> Bool {
        // Anything but `_ =` starts some other statement.
        guard tokens.current.kind == .identifier("_"), tokens.peek().isPunct(.assign) else { return false }
        tokens.advance()
        tokens.advance()
        return true
    }

    /// An expression, or an assignment to one.
    private func parseExpressionStatement() throws(ParseFailure) -> StmtKind {
        let target = try ExpressionParser(tokens: tokens).parseExpression()
        // An expression that no assignment operator follows is the whole statement.
        guard case .punct(let punct) = tokens.current.kind, let op = punct.assignOperator else {
            return .expression(target)
        }
        tokens.advance()
        return .assign(target: target, op: op, value: try ExpressionParser(tokens: tokens).parseExpression())
    }

    /// After the `if`: the condition, the block, and the `else` part, when there is one.
    private func parseIf() throws(ParseFailure) -> StmtKind {
        let condition = try ExpressionParser(tokens: tokens).parseExpression()
        let then = try parseBlock()
        let otherwise = tokens.consume(.else) ? try parseElse() : nil
        return .ifStmt(condition: condition, then: then, otherwise: otherwise)
    }

    /// After the `else`: a block, or an `if` that is the one statement of the block it stands for.
    private func parseElse() throws(ParseFailure) -> Block {
        // An `else` without an `if` after it takes a block of its own.
        guard tokens.current.isKeyword(.if) else { return try parseBlock() }
        let start = tokens.advance().range
        let nested = Stmt(kind: try parseIf(), range: tokens.range(from: start))
        // The nested `if` ends with the `}` of its last block, which ends this one too.
        return Block(statements: [nested], closingBrace: tokens.previousRange)
    }

    /// After the `let` or `var`: `binding (',' binding)*`.
    private func parseBindings() throws(ParseFailure) -> [Binding] {
        var bindings = [try parseBinding()]
        while tokens.consume(.comma) { bindings.append(try parseBinding()) }
        return bindings
    }

    /// `identifier (':' type)? ('=' expression)?`.
    private func parseBinding() throws(ParseFailure) -> Binding {
        let (name, nameRange) = try tokens.expectIdentifier(else: ErrorCode.missingBindingName)
        let type = tokens.consume(.colon) ? try TypeParser(tokens: tokens).parseType() : nil
        let value = tokens.consume(.assign) ? try ExpressionParser(tokens: tokens).parseExpression() : nil
        return Binding(name: name, nameRange: nameRange, type: type, value: value)
    }
}
