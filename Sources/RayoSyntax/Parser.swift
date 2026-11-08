import RayoDiagnostics
import RayoSource

/// A recursive-descent parser. It reports what it can't parse and recovers at the next statement, so one
/// run lists every syntax error.
public struct Parser {
    private var tokens: [Token]
    private var position = 0
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
        switch current.kind {
        case .invalid:
            // The lexer has reported it already.
            break
        case .unexpected(let character):
            diagnostics.append(.error("unexpected character '\(character)'", at: current.range))
        default:
            diagnostics.append(.error("\(message), found \(describe(current))", at: current.range))
        }
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

    // MARK: Sequences

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
            case .punct(.lbrace), .punct(.lparen):
                depth += 1
            case .punct(.rbrace):
                if depth == 0 { break loop }
                depth -= 1
            case .punct(.rparen):
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
        if consume(.let) {
            kind = .binding(try parseBinding(.let))
        } else if consume(.var) {
            kind = .binding(try parseBinding(.var))
        } else if consume(.if) {
            kind = try parseIf()
        } else if consume(.while) {
            let condition = try parseExpression()
            kind = .whileStmt(condition: condition, body: try parseBlock())
        } else if consume(.break) {
            kind = .breakStmt
        } else if consume(.continue) {
            kind = .continueStmt
        } else {
            kind = try parseExpressionStatement()
        }
        return Stmt(kind: kind, range: range(from: start))
    }

    /// An expression, or an assignment to one.
    private mutating func parseExpressionStatement() throws(Failure) -> StmtKind {
        let target = try parseExpression()
        guard case .punct(let p) = current.kind, let op = p.assignOperator else {
            return .expression(target)
        }
        advance()
        return .assign(target: target, op: op, value: try parseExpression())
    }

    private mutating func parseIf() throws(Failure) -> StmtKind {
        let condition = try parseExpression()
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

    /// After the `let` or `var`: `identifier (':' type)? '=' expression`.
    private mutating func parseBinding(_ kind: BindingKind) throws(Failure) -> Binding {
        let (name, nameRange) = try expectIdentifier("a name to bind")
        var type: TypeExpr?
        if consume(.colon) { type = try parseType() }
        guard consume(.assign) else { throw fail("expected '=' and a value") }
        return Binding(kind: kind, name: name, nameRange: nameRange, type: type, value: try parseExpression())
    }

    // MARK: Expressions

    mutating func parseExpression() throws(Failure) -> Expr {
        try parseBinary(minimumLevel: 1)
    }

    private mutating func parseBinary(minimumLevel: Int) throws(Failure) -> Expr {
        var left = try parseUnary()
        while case .punct(let p) = current.kind, let op = p.binaryOperator, op.level >= minimumLevel {
            advance()
            let right = try parseBinary(minimumLevel: op.level + 1)
            left = Expr(kind: .binary(op, left, right), range: left.range.to(right.range))
        }
        return left
    }

    /// `'-' int-literal`, `'copy' identifier`, `('-' | '!') unary`, or a primary expression.
    private mutating func parseUnary() throws(Failure) -> Expr {
        let start = current.range
        if current.isPunct(.minus), case .intLiteral(let digits) = peek().kind {
            advance()
            advance()
            return Expr(kind: .negativeIntLiteral(digits), range: range(from: start))
        }
        if consume(.copy) {
            let (name, nameRange) = try expectIdentifier("a name after 'copy'")
            return Expr(kind: .copy(name: name, nameRange: nameRange), range: range(from: start))
        }
        let op: UnaryOperator
        switch current.kind {
        case .punct(.minus): op = .negate
        case .punct(.bang): op = .not
        default: return try parsePrimary()
        }
        advance()
        let operand = try parseUnary()
        return Expr(kind: .unary(op, operand), range: range(from: start))
    }

    private mutating func parsePrimary() throws(Failure) -> Expr {
        let start = current.range
        switch current.kind {
        case .intLiteral(let value):
            advance()
            return Expr(kind: .intLiteral(value), range: start)
        case .keyword(.true):
            advance()
            return Expr(kind: .boolLiteral(true), range: start)
        case .keyword(.false):
            advance()
            return Expr(kind: .boolLiteral(false), range: start)
        case .identifier(let name):
            advance()
            guard consume(.lparen) else { return Expr(kind: .name(name), range: start) }
            return try parseCall(to: name, at: start)
        case .punct(.lparen):
            advance()
            return try parseParenthesized(from: start)
        default:
            throw fail("expected an expression")
        }
    }

    /// After the `(` that follows a name: the arguments, separated by commas with an optional trailing comma,
    /// and the `)`.
    private mutating func parseCall(to name: String, at nameRange: SourceRange) throws(Failure) -> Expr {
        var arguments: [Expr] = []
        while !current.isPunct(.rparen) {
            arguments.append(try parseExpression())
            if !consume(.comma) { break }
        }
        try expect(.rparen, "to close the arguments")
        return Expr(kind: .call(name: name, nameRange: nameRange, arguments: arguments), range: range(from: nameRange))
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private mutating func parseParenthesized(from start: SourceRange) throws(Failure) -> Expr {
        let inner = try parseExpression()
        try expect(.rparen, "to close the parenthesized expression")
        return Expr(kind: inner.kind, range: range(from: start))
    }
}

private extension BinaryOperator {
    /// How tightly the operator binds, from 1 for the loosest. Operators of one level group from the left.
    var level: Int {
        switch self {
        case .or: return 1
        case .and: return 2
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: return 3
        case .add, .subtract: return 4
        case .multiply, .divide, .remainder: return 5
        }
    }
}
