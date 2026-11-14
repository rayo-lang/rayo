internal import RayoDiagnostics
internal import RayoSource

/// Parses expressions, grouping operators by how tightly they bind.
extension Parser {
    mutating func parseExpression() throws(ParseFailure) -> Expr {
        try parseBinary(minimumLevel: 1)
    }

    /// Parses an expression whose binary operators outside parentheses all bind at `minimumLevel` or tighter.
    private mutating func parseBinary(minimumLevel: Int) throws(ParseFailure) -> Expr {
        var left = try parseUnary()
        // An operator takes the tighter ones after it as its right operand, so one level groups from the left.
        while case .punct(let punct) = current.kind, let op = punct.binaryOperator, op.level >= minimumLevel {
            advance()
            let right = try parseBinary(minimumLevel: op.level + 1)
            left = Expr(kind: .binary(op, left, right), range: left.range.to(right.range))
        }
        return left
    }

    /// `'-' int-literal`, `'copy' identifier ('.' member)*`, `('-' | '!') unary`, or a postfix expression.
    private mutating func parseUnary() throws(ParseFailure) -> Expr {
        let start = current.range

        // A `-` right before a literal is one literal, so `-9223372036854775808` is `Int.min`.
        if current.isPunct(.minus), case .intLiteral(let digits) = peek().kind {
            advance()
            advance()
            return Expr(kind: .negativeIntLiteral(digits), range: range(from: start))
        }
        // A `copy` takes the local it copies, or a field of it at any depth.
        if consume(.copy) {
            let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingCopiedName)
            let place = try parseMembers(of: Expr(kind: .name(name), range: nameRange))
            return Expr(kind: .copy(place), range: range(from: start))
        }
        // An expression without a `-` or `!` in front is a postfix one.
        guard case .punct(let punct) = current.kind, let op = punct.unaryOperator else {
            return try parsePostfix()
        }

        // A `-` or `!` applies to the unary expression after it.
        advance()
        let operand = try parseUnary()
        return Expr(kind: .unary(op, operand), range: range(from: start))
    }

    /// `primary postfix*`, where a postfix is `'.' member`, or `'(' arguments ')'` after a name, a member or an
    /// implicit member.
    private mutating func parsePostfix() throws(ParseFailure) -> Expr {
        // A parenthesized expression keeps the kind of the expression inside it, so `(f)` reads as the name `f`, but
        // it is no name or member, and nothing calls it until a member is taken of it.
        var isParenthesized = current.isPunct(.lparen)
        var value = try parsePrimary()

        // Each postfix applies to the value before it, so `a.b(1).c` is the `c` of the call `a.b(1)`.
        while true {
            switch current.kind {
            // A `.` takes a member of the value.
            case .punct(.dot):
                value = try parseMembers(of: value)
                isParenthesized = false

            // A `(` calls the value, where it is a name, a member or an implicit member written bare.
            case .punct(.lparen) where value.isCallable && !isParenthesized:
                value = try parseCall(to: value)

            // Anything else ends the expression.
            default:
                return value
            }
        }
    }

    /// After `base`: the members taken of it, each after a `.`.
    private mutating func parseMembers(of base: Expr) throws(ParseFailure) -> Expr {
        var value = base

        // Each `.` takes a member of the value before it, so `a.b.c` is the `c` of `a.b`.
        while consume(.dot) {
            let (name, nameRange) = try parseMemberName()
            value = Expr(kind: .member(value, name: name, nameRange: nameRange), range: value.range.to(nameRange))
        }
        return value
    }

    /// The member's name after a `.`, and its range.
    private mutating func parseMemberName() throws(ParseFailure) -> (String, SourceRange) {
        // A member's name is an identifier, a keyword or an integer literal; any other token is reported.
        guard let name = memberSpelling else { throw fail(ErrorCode.missingMemberName) }
        return (name, advance().range)
    }

    /// How the current token is spelled as a member's name after a `.`, when it can be one: an identifier, a keyword,
    /// or an integer literal as the source writes it.
    private var memberSpelling: String? {
        switch current.kind {
        case .intLiteral: text(of: current.range)
        default: current.labelSpelling
        }
    }

    private mutating func parsePrimary() throws(ParseFailure) -> Expr {
        switch current.kind {
        // An integer literal is the whole expression.
        case .intLiteral(let value):
            Expr(kind: .intLiteral(value), range: advance().range)

        // So is `true` or `false`.
        case .keyword(let keyword) where keyword == .true || keyword == .false:
            Expr(kind: .boolLiteral(keyword == .true), range: advance().range)

        // A name is a value's, or a callee where a `(` comes after it.
        case .identifier(let name):
            Expr(kind: .name(name), range: advance().range)

        // A `.` with no value before it starts an implicit member.
        case .punct(.dot):
            try parseImplicitMember(from: advance().range)

        // A `(` groups the expression inside it.
        case .punct(.lparen):
            try parseParenthesized(from: advance().range)

        // A `[` starts an array literal.
        case .punct(.lbracket):
            try parseArrayLiteral(from: advance().range)

        // An `if` gives the value of the branch that runs.
        case .keyword(.if):
            try parseIfExpression(from: advance().range)

        // Any other token starts no expression.
        default:
            throw fail(ErrorCode.missingExpression)
        }
    }

    /// After the `.` at `start`: the implicit member's name.
    private mutating func parseImplicitMember(from start: SourceRange) throws(ParseFailure) -> Expr {
        let (name, _) = try parseMemberName()
        return Expr(kind: .implicitMember(name: name), range: range(from: start))
    }

    /// At the `(` that follows `callee`: the `(`, the arguments and the `)`.
    private mutating func parseCall(to callee: Expr) throws(ParseFailure) -> Expr {
        advance()
        let arguments = try parseList(upTo: .rparen, ifUnclosed: ErrorCode.unclosedArguments) {
            parser throws(ParseFailure) in
            try parser.parseArgument()
        }
        return Expr(kind: .call(callee: callee, arguments: arguments), range: range(from: callee.range))
    }

    /// `(label ':')? expression`, where a label may be a keyword.
    private mutating func parseArgument() throws(ParseFailure) -> Argument {
        let start = current.range
        let label = parseArgumentLabel()
        let value = try parseExpression()
        return Argument(label: label, value: value, range: range(from: start))
    }

    /// Parses `label ':'` before an argument's value, when it comes next, and returns the label.
    private mutating func parseArgumentLabel() -> String? {
        // A value with no `label:` in front of it has no label.
        guard let spelling = current.labelSpelling, peek().isPunct(.colon) else { return nil }
        advance()
        advance()
        return spelling
    }

    /// After the `[` at `start`: the array literal's elements and the `]`.
    private mutating func parseArrayLiteral(from start: SourceRange) throws(ParseFailure) -> Expr {
        let elements = try parseList(upTo: .rbracket, ifUnclosed: ErrorCode.unclosedArrayLiteral) {
            parser throws(ParseFailure) in
            try parser.parseExpression()
        }
        return Expr(kind: .arrayLiteral(elements), range: range(from: start))
    }

    /// After the `if` at `start`: the `if` as an expression.
    private mutating func parseIfExpression(from start: SourceRange) throws(ParseFailure) -> Expr {
        let ifExpr = try parseIf()
        return Expr(kind: .if(ifExpr), range: range(from: start))
    }

    /// After the `if`: the condition, the block, and the `else` part, when there is one.
    mutating func parseIf() throws(ParseFailure) -> IfExpr {
        let condition = try parseExpression()
        let then = try parseBlock()
        let otherwise = consume(.else) ? try parseElse() : nil
        return IfExpr(condition: condition, then: then, otherwise: otherwise)
    }

    /// After the `else`: a block, or an `if` that is the one statement of the block it stands for.
    private mutating func parseElse() throws(ParseFailure) -> Block {
        // An `else` without an `if` after it takes a block of its own.
        guard current.isKeyword(.if) else { return try parseBlock() }
        let start = advance().range
        let nested = Stmt(kind: .ifStmt(try parseIf()), range: range(from: start))
        // The nested `if` ends with the `}` of its last block, which ends this one too.
        return Block(statements: [nested], closingBrace: previousRange)
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private mutating func parseParenthesized(from start: SourceRange) throws(ParseFailure) -> Expr {
        let inner = try parseExpression()
        try expect(.rparen, else: ErrorCode.unclosedParenthesizedExpression)
        return Expr(kind: inner.kind, range: range(from: start))
    }
}

private extension Expr {
    /// Whether a `(` after the expression calls it: a name, a member and an implicit member can be called.
    var isCallable: Bool {
        switch kind {
        case .name, .member, .implicitMember: true
        default: false
        }
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
