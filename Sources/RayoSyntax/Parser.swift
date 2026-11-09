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

    /// The `ErrorCode` case of a syntax error, which takes what the parser found where it expected something
    /// else.
    private typealias SyntaxErrorCase = (FoundToken) -> ErrorCode

    @discardableResult
    private mutating func expect(_ punct: Punct, else error: SyntaxErrorCase) throws(Failure) -> Token {
        guard current.isPunct(punct) else { throw fail(error) }
        return advance()
    }

    private mutating func expectIdentifier(else error: SyntaxErrorCase) throws(Failure) -> (String, SourceRange) {
        guard case .identifier(let name) = current.kind else { throw fail(error) }
        return (name, advance().range)
    }

    /// Reports `error` at the current token, or the unexpected character the token is.
    private mutating func fail(_ error: SyntaxErrorCase) -> Failure {
        switch current.kind {
        case .invalid:
            // The lexer has reported it already.
            break
        case .unexpected(let character):
            report(.unexpectedCharacter(character: character))
        default:
            report(error(describe(current)))
        }
        return Failure()
    }

    private mutating func report(_ code: ErrorCode) {
        diagnostics.append(Diagnostic(code, at: current.range))
    }

    private func describe(_ token: Token) -> FoundToken {
        switch token.kind {
        case .newline: return .newline
        case .eof: return .endOfFile
        default: return .token(token.description)
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
    private mutating func parseSequence<T>(ifUnended unended: SyntaxErrorCase,
                                           _ item: (inout Parser) throws(Failure) -> T) -> [T] {
        var items: [T] = []
        skipSeparators()
        while !current.isPunct(.rbrace) && !atEnd {
            do {
                items.append(try item(&self))
                if !atStatementEnd { throw fail(unended) }
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
            functions += parseSequence(ifUnended: ErrorCode.unendedDeclaration) { parser throws(Failure) in
                try parser.parseFunction()
            }
            if atEnd { return SourceFile(functions: functions) }
            report(.unmatchedBrace)
            advance()
        }
    }

    /// `'func' identifier '(' parameters ')' ('->' type)? block`.
    private mutating func parseFunction() throws(Failure) -> FuncDecl {
        guard consume(.func) else { throw fail(ErrorCode.missingFunc) }
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingFunctionName)
        try expect(.lparen, else: ErrorCode.missingParameterList)
        var parameters: [Param] = []
        while !current.isPunct(.rparen) {
            parameters.append(try parseParameter())
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: ErrorCode.unclosedParameters)
        var result: TypeExpr?
        if consume(.arrow) { result = try parseType() }
        let body = try parseBlock()
        return FuncDecl(name: name, nameRange: nameRange, parameters: parameters, result: result, body: body)
    }

    /// `(label | '_')? identifier ':' ('mutable' | 'owned')? type ('=' expression)?`, where a label may be a
    /// keyword.
    private mutating func parseParameter() throws(Failure) -> Param {
        let start = current.range
        var label: String?
        var isLabelWritten = false
        if let spelling = labelSpelling(of: current), case .identifier = peek().kind {
            advance()
            label = spelling == "_" ? nil : spelling
            isLabelWritten = true
        }
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingParameterName)
        if !isLabelWritten && name != "_" { label = name }
        guard consume(.colon) else { throw fail(ErrorCode.missingParameterType) }
        let convention = parseConvention()
        let type = try parseType()
        let defaultValue = consume(.assign) ? try parseExpression() : nil
        return Param(label: label, name: name, nameRange: nameRange, convention: convention,
                     type: type, defaultValue: defaultValue, range: range(from: start))
    }

    /// `mutable` or `owned`, which are names everywhere but before a parameter's type.
    private mutating func parseConvention() -> ParamConvention? {
        guard case .identifier(let word) = current.kind, let convention = ParamConvention(rawValue: word) else {
            return nil
        }
        switch peek().kind {
        case .identifier, .punct(.lparen):
            advance()
            return convention
        default:
            return nil
        }
    }

    /// How `token` is spelled as an argument label: any identifier or keyword is one.
    private func labelSpelling(of token: Token) -> String? {
        switch token.kind {
        case .identifier(let name): return name
        case .keyword(let keyword): return keyword.rawValue
        default: return nil
        }
    }

    // MARK: Types

    /// `identifier` or `'(' ')'`.
    mutating func parseType() throws(Failure) -> TypeExpr {
        let start = current.range
        if consume(.lparen) {
            try expect(.rparen, else: ErrorCode.unclosedEmptyParentheses)
            return .void(range: range(from: start))
        }
        let (name, _) = try expectIdentifier(else: ErrorCode.missingType)
        return .named(name, range: range(from: start))
    }

    // MARK: Statements

    private mutating func parseBlock() throws(Failure) -> Block {
        try expect(.lbrace, else: ErrorCode.missingBlock)
        let statements = parseStatements()
        let closingBrace = try expect(.rbrace, else: ErrorCode.unclosedBlock).range
        return Block(statements: statements, closingBrace: closingBrace)
    }

    private mutating func parseStatements() -> [Stmt] {
        parseSequence(ifUnended: ErrorCode.unendedStatement) { parser throws(Failure) in try parser.parseStatement() }
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
        } else if consume(.return) {
            kind = .returnStmt(atStatementEnd ? nil : try parseExpression())
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
                let nested = Stmt(kind: try parseIf(), range: range(from: start))
                // The nested 'if' ends with the '}' of its last block, which ends this one too.
                otherwise = Block(statements: [nested], closingBrace: tokens[position - 1].range)
            } else {
                otherwise = try parseBlock()
            }
        }
        return .ifStmt(condition: condition, then: then, otherwise: otherwise)
    }

    /// After the `let` or `var`: `identifier (':' type)? '=' expression`.
    private mutating func parseBinding(_ kind: BindingKind) throws(Failure) -> Binding {
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingBindingName)
        var type: TypeExpr?
        if consume(.colon) { type = try parseType() }
        guard consume(.assign) else { throw fail(ErrorCode.missingBindingValue) }
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
            let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingCopiedName)
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
            throw fail(ErrorCode.missingExpression)
        }
    }

    /// After the `(` that follows a name: the arguments, separated by commas with an optional trailing comma,
    /// and the `)`.
    private mutating func parseCall(to name: String, at nameRange: SourceRange) throws(Failure) -> Expr {
        var arguments: [Argument] = []
        while !current.isPunct(.rparen) {
            arguments.append(try parseArgument())
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: ErrorCode.unclosedArguments)
        return Expr(kind: .call(name: name, nameRange: nameRange, arguments: arguments), range: range(from: nameRange))
    }

    /// `(label ':')? expression`, where a label may be a keyword.
    private mutating func parseArgument() throws(Failure) -> Argument {
        let start = current.range
        var label: String?
        if let spelling = labelSpelling(of: current), peek().isPunct(.colon) {
            advance()
            advance()
            label = spelling
        }
        let value = try parseExpression()
        return Argument(label: label, value: value, range: range(from: start))
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private mutating func parseParenthesized(from start: SourceRange) throws(Failure) -> Expr {
        let inner = try parseExpression()
        try expect(.rparen, else: ErrorCode.unclosedParenthesizedExpression)
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
