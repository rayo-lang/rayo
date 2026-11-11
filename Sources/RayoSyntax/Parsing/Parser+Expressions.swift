import RayoDiagnostics
import RayoSource

/// Parses expressions, grouping operators by how tightly they bind.
extension Parser {
    func parseExpression() throws(ParseFailure) -> Expr {
        try parseBinary(minimumLevel: 1)
    }

    /// Parses an expression whose binary operators outside parentheses all bind at `minimumLevel` or tighter.
    private func parseBinary(minimumLevel: Int) throws(ParseFailure) -> Expr {
        var left = try parseUnary()
        // An operator takes the tighter ones after it as its right operand, so one level groups from the left.
        while case .punct(let punct) = current.kind, let op = punct.binaryOperator, op.level >= minimumLevel {
            advance()
            let right = try parseBinary(minimumLevel: op.level + 1)
            left = Expr(kind: .binary(op, left, right), range: left.range.to(right.range))
        }
        return left
    }

    /// `'-' int-literal`, `'copy' identifier`, `('-' | '!') unary`, or a primary expression.
    private func parseUnary() throws(ParseFailure) -> Expr {
        let start = current.range

        // A `-` right before a literal is one literal, so `-9223372036854775808` is `Int.min`.
        if current.isPunct(.minus), case .intLiteral(let digits) = peek().kind {
            advance()
            advance()
            return Expr(kind: .negativeIntLiteral(digits), range: range(from: start))
        }
        // A `copy` takes the name of the local it copies.
        if consume(.copy) {
            let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingCopiedName)
            return Expr(kind: .copy(name: name, nameRange: nameRange), range: range(from: start))
        }
        // An expression without a `-` or `!` in front is a primary one.
        guard case .punct(let punct) = current.kind, let op = punct.unaryOperator else {
            return try parsePrimary()
        }

        // A `-` or `!` applies to the unary expression after it.
        advance()
        let operand = try parseUnary()
        return Expr(kind: .unary(op, operand), range: range(from: start))
    }

    private func parsePrimary() throws(ParseFailure) -> Expr {
        let start = current.range
        switch current.kind {
        // An integer literal is the whole expression.
        case .intLiteral(let value):
            advance()
            return Expr(kind: .intLiteral(value), range: start)

        // So is `true` or `false`.
        case .keyword(let keyword) where keyword == .true || keyword == .false:
            advance()
            return Expr(kind: .boolLiteral(keyword == .true), range: start)

        // A name is a call when a `(` comes after it.
        case .identifier(let name):
            advance()
            // Without a `(`, the name is a value's.
            guard consume(.lparen) else { return Expr(kind: .name(name), range: start) }
            return try parseCall(to: name, at: start)

        // A `(` groups the expression inside it.
        case .punct(.lparen):
            advance()
            return try parseParenthesized(from: start)

        // Any other token starts no expression.
        default:
            throw fail(ErrorCode.missingExpression)
        }
    }

    /// After the `(` that follows a name: the arguments and the `)`.
    private func parseCall(to name: String, at nameRange: SourceRange) throws(ParseFailure) -> Expr {
        let arguments = try parseList(ifUnclosed: ErrorCode.unclosedArguments) {
            () throws(ParseFailure) in try parseArgument()
        }
        let kind = ExprKind.call(name: name, nameRange: nameRange, arguments: arguments)
        return Expr(kind: kind, range: range(from: nameRange))
    }

    /// `(label ':')? expression`, where a label may be a keyword.
    private func parseArgument() throws(ParseFailure) -> Argument {
        let start = current.range
        let label = parseArgumentLabel()
        let value = try parseExpression()
        return Argument(label: label, value: value, range: range(from: start))
    }

    /// Parses `label ':'` before an argument's value, when it comes next, and returns the label.
    private func parseArgumentLabel() -> String? {
        // A value with no `label:` in front of it has no label.
        guard let spelling = current.labelSpelling, peek().isPunct(.colon) else { return nil }
        advance()
        advance()
        return spelling
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private func parseParenthesized(from start: SourceRange) throws(ParseFailure) -> Expr {
        let inner = try parseExpression()
        try expect(.rparen, else: ErrorCode.unclosedParenthesizedExpression)
        return Expr(kind: inner.kind, range: range(from: start))
    }
}

private extension BinaryOperator {
    /// How tightly the operator binds, from 1 for the loosest.
    var level: Int {
        switch self {
        case .or: 1
        case .and: 2
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: 3
        case .add, .subtract: 4
        case .multiply, .divide, .remainder: 5
        }
    }
}
