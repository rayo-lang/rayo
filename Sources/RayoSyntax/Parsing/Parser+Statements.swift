internal import RayoDiagnostics

/// Parses blocks and the statements in them.
extension Parser {
    mutating func parseBlock() throws(ParseFailure) -> Block {
        try expect(.lbrace, else: ErrorCode.missingBlock)
        let statements = parseStatements()
        let closingBrace = try expect(.rbrace, else: ErrorCode.unclosedBlock).range
        return Block(statements: statements, closingBrace: closingBrace)
    }

    /// Parses a block's statements, with an error statement in place of each that fails.
    private mutating func parseStatements() -> [Stmt] {
        parseLines(ifUnended: ErrorCode.unendedStatement) { parser throws(StatementFailure) in
            let statement = try parser.parseStatement()
            // A statement that runs on past its end fails whole, since the source it leaves out may change what it
            // means. It still binds the names it declares.
            if !parser.atStatementEnd {
                _ = parser.fail(ErrorCode.unendedStatement)
                throw StatementFailure(boundNames: statement.boundNames)
            }
            return statement
        } ifFailed: { failure, range in
            Stmt(kind: .error(boundNames: failure.boundNames), range: range)
        }
    }

    private mutating func parseStatement() throws(StatementFailure) -> Stmt {
        let start = current.range
        let kind = if let bindingKind = consumeBindingKeyword() {
            StmtKind.declaration(bindingKind, try parseBindings())
        } else {
            try parseNonDeclaration()
        }
        return Stmt(kind: kind, range: range(from: start))
    }

    /// Consumes the `let` or `var` that starts a declaration, when one comes next, and gives the kind it declares: a
    /// `let`'s bindings never change, and a `var`'s can.
    private mutating func consumeBindingKeyword() -> BindingKind? {
        if consume(.let) { .let } else if consume(.var) { .var } else { nil }
    }

    /// Parses a statement other than a declaration. It binds no name, so its failure carries none.
    private mutating func parseNonDeclaration() throws(StatementFailure) -> StmtKind {
        do throws(ParseFailure) {
            return if consume(.if) {
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
        } catch {
            throw StatementFailure()
        }
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

    /// After the `let` or `var`: `binding (',' binding)*`. A failure carries the names bound before it.
    private mutating func parseBindings() throws(StatementFailure) -> [Binding] {
        var bindings = [try parseBinding(after: [])]
        while consume(.comma) { bindings.append(try parseBinding(after: bindings)) }
        return bindings
    }

    /// `identifier (':' type)? ('=' expression)?`, after the bindings `bound` of the same declaration. A binding that
    /// fails after its name still binds it.
    private mutating func parseBinding(after bound: [Binding]) throws(StatementFailure) -> Binding {
        let boundNames = bound.map(\.name)
        guard let (name, nameRange) = try? expectIdentifier(else: ErrorCode.missingBindingName) else {
            throw StatementFailure(boundNames: boundNames)
        }

        do {
            let type = consume(.colon) ? try parseType() : nil
            let value = consume(.assign) ? try parseExpression() : nil
            return Binding(name: name, nameRange: nameRange, type: type, value: value)
        } catch {
            throw StatementFailure(boundNames: boundNames + [name])
        }
    }
}

private extension Stmt {
    /// The names the statement binds: a declaration's, and none for any other statement.
    var boundNames: [String] {
        guard case .declaration(_, let bindings) = kind else { return [] }
        return bindings.map(\.name)
    }
}
