import RayoDiagnostics
import RayoSource

/// A recursive-descent parser. It reports what it can't parse and recovers at the next statement, so one
/// run lists every syntax error.
public struct Parser {
    private var tokens: [Token]
    private var position = 0
    private var nextID = 0
    public private(set) var diagnostics: [Diagnostic]

    /// Thrown once the error is in `diagnostics`; the statement that failed is skipped.
    struct Failure: Error {}

    public init(_ source: String) {
        self.init(Array(source.utf8))
    }

    /// A parser for source held as UTF-8, which reports where it isn't.
    public init(_ bytes: [UInt8]) {
        let (tokens, diagnostics) = Lexer.tokenize(bytes)
        self.tokens = tokens
        self.diagnostics = diagnostics
    }

    public static func parse(_ source: String) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        parse(Array(source.utf8))
    }

    /// Parses `bytes`, with the lexer's and the parser's diagnostics in source order.
    public static func parse(_ bytes: [UInt8]) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        var parser = Parser(bytes)
        let file = parser.parseFile()
        let ordered = parser.diagnostics.enumerated().sorted { a, b in
            (a.element.range.start.offset, a.offset) < (b.element.range.start.offset, b.offset)
        }
        return (file, ordered.map(\.element))
    }

    // MARK: Tokens

    private var current: Token { tokens[position] }
    private var atEnd: Bool { current.kind == .eof }

    private func peek(_ ahead: Int = 1) -> Token {
        tokens[min(position + ahead, tokens.count - 1)]
    }

    @discardableResult
    private mutating func advance() -> Token {
        let token = tokens[position]
        if position < tokens.count - 1 { position += 1 }
        return token
    }

    private mutating func consume(_ punct: Punct) -> Bool {
        guard current.isPunct(punct) else { return false }
        advance()
        return true
    }

    private mutating func consume(_ keyword: Keyword) -> Bool {
        guard current.isKeyword(keyword) else { return false }
        advance()
        return true
    }

    @discardableResult
    private mutating func expect(_ punct: Punct, _ context: String) throws(Failure) -> Token {
        guard current.isPunct(punct) else { throw fail("expected '\(punct.rawValue)' \(context)") }
        return advance()
    }

    private mutating func expectIdentifier(_ what: String) throws(Failure) -> (String, SourceRange) {
        guard case .identifier(let name) = current.kind else { throw fail("expected \(what)") }
        return (name, advance().range)
    }

    /// Reports `message`, followed by what was found at the current token instead.
    private mutating func fail(_ message: String) -> Failure {
        // The lexer has reported an invalid token already.
        guard current.kind != .invalid else { return Failure() }
        return error("\(message), found \(describe(current))", at: current.range)
    }

    private mutating func unsupported(_ what: String, at range: SourceRange) -> Failure {
        error("\(what) isn't supported yet", at: range)
    }

    private mutating func error(_ message: String, at range: SourceRange) -> Failure {
        diagnostics.append(.error(message, at: range))
        return Failure()
    }

    private func describe(_ token: Token) -> String {
        switch token.kind {
        case .newline: return "a newline"
        case .eof: return "the end of the file"
        default: return "'\(token)'"
        }
    }

    private var atStatementEnd: Bool {
        current.kind == .newline || current.isPunct(.semicolon) || current.isPunct(.rbrace) || atEnd
    }

    private mutating func skipSeparators() {
        while current.kind == .newline || current.isPunct(.semicolon) { advance() }
    }

    private var previousEnd: SourceLocation { tokens[max(position - 1, 0)].range.end }

    private func range(from start: SourceRange) -> SourceRange { SourceRange(start.start, previousEnd) }

    private mutating func makeExpr(_ kind: ExprKind, _ range: SourceRange) -> Expr {
        defer { nextID += 1 }
        return Expr(id: ExprID(nextID), kind: kind, range: range)
    }

    /// The lexer keeps `>` alone, so a `>` directly followed by `=` is `>=`.
    private var atGreaterEqual: Bool {
        current.isPunct(.greater) && peek().isPunct(.assign) && !peek().spaceBefore
    }

    private var atOwnedBinding: Bool {
        current.isKeyword(.owned) && (peek().isKeyword(.let) || peek().isKeyword(.var))
    }

    // MARK: Lists and sequences

    /// After an opening bracket: items separated by commas, with an optional trailing comma, and the
    /// `closing` bracket.
    private mutating func parseList<T>(closing: Punct, _ context: String,
                                       _ item: (inout Parser) throws(Failure) -> T) throws(Failure) -> [T] {
        var items: [T] = []
        while !current.isPunct(closing) {
            items.append(try item(&self))
            if !consume(.comma) { break }
        }
        try expect(closing, context)
        return items
    }

    /// Items separated by newlines or `;`, up to the `}` that closes their block or the end of the file,
    /// which it leaves for the caller. An item that fails is skipped, and its error stays reported.
    private mutating func parseSequence<T>(of what: String, _ item: (inout Parser) throws(Failure) -> T) -> [T] {
        var items: [T] = []
        skipSeparators()
        while !current.isPunct(.rbrace) && !atEnd {
            do {
                items.append(try item(&self))
                if !atStatementEnd { throw fail("expected a newline or ';' after the \(what)") }
            } catch {
                recover()
            }
            skipSeparators()
        }
        return items
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it or the `}` that closes
    /// its block.
    private mutating func recover() {
        let start = position
        var depth = 0
        loop: while !atEnd {
            switch current.kind {
            case .punct(.lbrace), .punct(.lparen), .punct(.lbracket):
                depth += 1
            case .punct(.rbrace):
                if depth == 0 { break loop }
                depth -= 1
            case .punct(.rparen), .punct(.rbracket):
                if depth > 0 { depth -= 1 }
            case .newline, .punct(.semicolon):
                if depth == 0 { break loop }
            default:
                break
            }
            advance()
        }
        if position == start && !atStatementEnd { advance() }
    }

    // MARK: Declarations

    mutating func parseFile() -> SourceFile {
        var functions: [FuncDecl] = []
        while true {
            functions += parseSequence(of: "declaration") { parser throws(Failure) in try parser.parseFunction() }
            if atEnd { return SourceFile(functions: functions) }
            diagnostics.append(.error("unmatched '}'", at: current.range))
            advance()
        }
    }

    /// `'func' identifier '(' ')' ('->' type)? block`.
    private mutating func parseFunction() throws(Failure) -> FuncDecl {
        guard current.isKeyword(.func) else { throw fail("expected 'func' to begin a declaration") }
        let start = advance().range
        let (name, nameRange) = try expectIdentifier("the function's name")
        try expect(.lparen, "after the function's name")
        try expect(.rparen, "after '('")
        var result: TypeExpr?
        if consume(.arrow) { result = try parseType() }
        let body = try parseBlock()
        return FuncDecl(name: name, nameRange: nameRange, result: result, body: body, range: range(from: start))
    }

    // MARK: Types

    /// `identifier` or `'(' ')'`.
    mutating func parseType() throws(Failure) -> TypeExpr {
        let start = current.range
        if consume(.lparen) {
            try expect(.rparen, "after '('")
            return .void(range: range(from: start))
        }
        let (name, _) = try expectIdentifier("a type")
        return .named(name, range: range(from: start))
    }

    // MARK: Statements

    private mutating func parseBlock() throws(Failure) -> Block {
        let start = try expect(.lbrace, "to begin a block").range
        let statements = parseStatements()
        try expect(.rbrace, "to close the block")
        return Block(statements: statements, range: range(from: start))
    }

    private mutating func parseStatements() -> [Stmt] {
        parseSequence(of: "statement") { parser throws(Failure) in try parser.parseStatement() }
    }

    private mutating func parseStatement() throws(Failure) -> Stmt {
        let start = current.range
        let kind: StmtKind
        if atOwnedBinding {
            let message = "a declaration takes its value without 'owned'"
            // Only a 'let' can borrow shared, so only a 'let' gets the hint.
            throw error(peek().isKeyword(.let) ? "\(message); write 'borrow' after '=' to borrow instead" : message,
                        at: start)
        } else if consume(.let) {
            kind = .binding(try parseBinding(.let))
        } else if consume(.var) {
            kind = .binding(try parseBinding(.var))
        } else if consume(.if) {
            kind = try parseIf()
        } else if consume(.while) {
            let condition = try parseCondition()
            kind = .whileStmt(condition: condition, body: try parseBlock())
        } else if consume(.for) {
            kind = try parseFor()
        } else if consume(.return) {
            kind = .returnStmt(atStatementEnd ? nil : try parseExpression())
        } else if consume(.break) {
            kind = .breakStmt
        } else if consume(.continue) {
            kind = .continueStmt
        } else if consume(.do) {
            kind = .doBlock(try parseBlock())
            if current.isKeyword(.catch) { throw unsupported("'catch'", at: current.range) }
        } else {
            kind = try parseExpressionStatement()
        }
        return Stmt(kind: kind, range: range(from: start))
    }

    /// After the `for`: `identifier 'in' lower '..<' upper block`.
    private mutating func parseFor() throws(Failure) -> StmtKind {
        let (name, nameRange) = try expectIdentifier("the loop variable")
        guard consume(.in) else { throw fail("expected 'in' after the loop variable") }
        let lower = try parseBinary(minimumLevel: 6)
        guard consume(.halfOpenRange) else {
            throw fail("expected '..<': the one loop supported so far is 'for i in a..<b'")
        }
        let upper = try parseBinary(minimumLevel: 6)
        return .forRange(name: name, nameRange: nameRange, lower: lower, upper: upper, body: try parseBlock())
    }

    /// An expression, or an assignment to one.
    private mutating func parseExpressionStatement() throws(Failure) -> StmtKind {
        let target = try parseExpression()
        guard case .punct(let p) = current.kind, p.isAssignment else { return .expression(target) }
        guard let op = AssignOperator(rawValue: p.rawValue) else { throw unsupported("'\(p.rawValue)'", at: current.range) }
        advance()
        return .assign(target: target, op: op, value: try parseExpression())
    }

    /// The condition of an `if` or `while`, which the statement's block follows.
    private mutating func parseCondition() throws(Failure) -> Expr {
        if current.isKeyword(.let) || current.isKeyword(.var) || current.isKeyword(.case) || atOwnedBinding {
            throw unsupported("a binding condition", at: current.range)
        }
        let condition = try parseExpression()
        if current.isPunct(.comma) { throw unsupported("a condition list", at: current.range) }
        return condition
    }

    private mutating func parseIf() throws(Failure) -> StmtKind {
        let condition = try parseCondition()
        let then = try parseBlock()
        var otherwise: Block?
        if consume(.else) {
            if current.isKeyword(.if) {
                let start = advance().range
                let nested = try parseIf()
                let nestedRange = range(from: start)
                otherwise = Block(statements: [Stmt(kind: nested, range: nestedRange)], range: nestedRange)
            } else {
                otherwise = try parseBlock()
            }
        }
        return .ifStmt(condition: condition, then: then, otherwise: otherwise)
    }

    /// After the `let` or `var`.
    private mutating func parseBinding(_ kind: BindingKind) throws(Failure) -> Binding {
        let (name, nameRange) = try expectIdentifier("a name to bind")
        var type: TypeExpr?
        if consume(.colon) { type = try parseType() }
        var value: Expr?
        if consume(.assign) {
            value = current.isKeyword(.borrow) ? try parseBorrowingInitializer(of: kind) : try parseExpression()
        }
        if current.isPunct(.comma) { throw unsupported("more than one binding in a declaration", at: current.range) }
        return Binding(kind: kind, name: name, nameRange: nameRange, type: type, value: value)
    }

    /// `'borrow' unary-expression`, the initializer of a `let` that borrows. The initializer may go on only
    /// with `??`, which is reported as unsupported, so the borrowed place ends it.
    private mutating func parseBorrowingInitializer(of kind: BindingKind) throws(Failure) -> Expr {
        let start = advance().range
        if kind == .var {
            // '=' on a 'var' that borrows writes the place it names, which a shared borrow can't.
            throw error("a 'var' can't borrow shared; write 'let', or '&' to lend the place for change", at: start)
        }
        let place = try parseUnary()
        if current.isPunct(.coalesce) { throw unsupported("'??'", at: current.range) }
        if !atStatementEnd && !current.isPunct(.comma) {
            let message = "a borrowing initializer ends after the place it borrows"
            if atGreaterEqual { throw error("\(message), found '>='", at: current.range) }
            throw fail(message)
        }
        return makeExpr(.borrow(place), range(from: start))
    }

    // MARK: Expressions

    mutating func parseExpression() throws(Failure) -> Expr {
        try parseBinary(minimumLevel: 1)
    }

    /// The binary operator at the current token, its precedence level, from 1 for the loosest, and how many
    /// tokens it spans.
    private func binaryOperator() -> (op: BinaryOperator, level: Int, width: Int)? {
        if atGreaterEqual { return (.greaterEqual, 4, 2) }
        guard case .punct(let p) = current.kind else { return nil }
        switch p {
        case .orOr: return (.or, 2, 1)
        case .andAnd: return (.and, 3, 1)
        case .equal: return (.equal, 4, 1)
        case .notEqual: return (.notEqual, 4, 1)
        case .less: return (.less, 4, 1)
        case .lessEqual: return (.lessEqual, 4, 1)
        case .greater: return (.greater, 4, 1)
        case .plus: return (.add, 6, 1)
        case .minus: return (.subtract, 6, 1)
        case .star: return (.multiply, 7, 1)
        case .slash: return (.divide, 7, 1)
        case .percent: return (.remainder, 7, 1)
        default: return nil
        }
    }

    private mutating func parseBinary(minimumLevel: Int) throws(Failure) -> Expr {
        var left = try parseUnary()
        while let (op, level, width) = binaryOperator(), level >= minimumLevel {
            for _ in 0..<width { advance() }
            // The lexer keeps the newline after a '>' at the end of a line; after a comparison, the line goes on.
            if op == .greater || op == .greaterEqual, current.kind == .newline { advance() }
            let right = try parseBinary(minimumLevel: level + 1)
            left = makeExpr(.binary(op, left, right), left.range.to(right.range))
        }
        if minimumLevel == 1, case .punct(let p) = current.kind, p.isBinaryOperator {
            throw unsupported("'\(p.rawValue)'", at: current.range)
        }
        return left
    }

    private mutating func parseUnary() throws(Failure) -> Expr {
        let start = current.range
        if current.isPunct(.minus), case .intLiteral(let digits) = peek().kind {
            advance()
            let operand = try parsePostfix()
            let range = SourceRange(start.start, operand.range.end)
            if case .intLiteral = operand.kind { return makeExpr(.negativeIntLiteral(digits), range) }
            return makeExpr(.unary(.negate, operand), range)
        }
        let make: ((Expr) -> ExprKind)?
        switch current.kind {
        case .punct(.minus): make = { .unary(.negate, $0) }
        case .punct(.bang): make = { .unary(.not, $0) }
        case .punct(.amp): make = { .lend($0) }
        case .keyword(.copy): make = { .copy($0) }
        case .keyword(.consume): make = { .consume($0) }
        case .keyword(.borrow):
            throw error("'borrow' is written only to begin the initializer of a local 'let'", at: start)
        default: make = nil
        }
        guard let make else { return try parsePostfix() }
        advance()
        let operand = try parseUnary()
        return makeExpr(make(operand), SourceRange(start.start, operand.range.end))
    }

    private mutating func parsePostfix() throws(Failure) -> Expr {
        var expr = try parsePrimary()
        while true {
            if consume(.dot) {
                let (name, nameRange) = try parseMemberName()
                expr = makeExpr(.member(expr, name: name, nameRange: nameRange),
                                SourceRange(expr.range.start, nameRange.end))
            } else if consume(.lparen) {
                let arguments = try parseList(closing: .rparen, "to close the arguments") { parser throws(Failure) in
                    try parser.parseArgument()
                }
                expr = makeExpr(.call(callee: expr, arguments: arguments), range(from: expr.range))
            } else if consume(.lbracket) {
                let arguments = try parseList(closing: .rbracket, "to close the index") { parser throws(Failure) in
                    try parser.parseArgument()
                }
                expr = makeExpr(.index(expr, arguments: arguments), range(from: expr.range))
            } else if current.isPunct(.question) {
                throw unsupported("optional chaining", at: current.range)
            } else if current.isPunct(.bang) {
                throw unsupported("force unwrapping", at: current.range)
            } else {
                return expr
            }
        }
    }

    /// After a `.`: an identifier, or a keyword, as in `.init`.
    private mutating func parseMemberName() throws(Failure) -> (String, SourceRange) {
        switch current.kind {
        case .identifier(let name): return (name, advance().range)
        case .keyword(let keyword): return (keyword.rawValue, advance().range)
        default: throw fail("expected a member name after '.'")
        }
    }

    /// `(arg-label ':')? expression`, where the label may be a keyword.
    private mutating func parseArgument() throws(Failure) -> Argument {
        var label: String?
        if peek().isPunct(.colon) {
            switch current.kind {
            case .identifier(let name): label = name
            case .keyword(let keyword): label = keyword.rawValue
            default: break
            }
            if label != nil {
                advance()
                advance()
            }
        }
        return Argument(label: label, value: try parseExpression())
    }

    private mutating func parsePrimary() throws(Failure) -> Expr {
        let start = current.range
        switch current.kind {
        case .intLiteral(let value):
            advance()
            return makeExpr(.intLiteral(value), start)
        case .keyword(.true):
            advance()
            return makeExpr(.boolLiteral(true), start)
        case .keyword(.false):
            advance()
            return makeExpr(.boolLiteral(false), start)
        case .keyword(.self):
            advance()
            return makeExpr(.selfRef, start)
        case .identifier(let name):
            advance()
            return makeExpr(.name(name), start)
        case .punct(.lparen):
            advance()
            return try parseParenthesized(from: start)
        case .punct(.lbracket):
            advance()
            let elements = try parseList(closing: .rbracket, "to close the array literal") { parser throws(Failure) in
                try parser.parseExpression()
            }
            return makeExpr(.arrayLiteral(elements), range(from: start))
        case .keyword(.if), .keyword(.when):
            throw unsupported("'\(current)' as an expression", at: current.range)
        default:
            throw fail("expected an expression")
        }
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private mutating func parseParenthesized(from start: SourceRange) throws(Failure) -> Expr {
        if current.isPunct(.rparen) { throw unsupported("the empty tuple", at: SourceRange(start.start, current.range.end)) }
        let inner = try parseExpression()
        if current.isPunct(.comma) { throw unsupported("a tuple", at: current.range) }
        try expect(.rparen, "to close the parenthesized expression")
        return Expr(id: inner.id, kind: inner.kind, range: range(from: start))
    }
}
