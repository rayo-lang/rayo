/// A recursive-descent parser. It reports what it can't parse and recovers at the next statement, so one
/// run lists every syntax error.
public struct Parser {
    private var tokens: [Token]
    private var position = 0
    private var nextID = 0
    /// False in an expression that a statement's block follows, such as an `if` condition, where `{` starts
    /// the block. Brackets and closure bodies allow trailing closures again.
    private var allowsTrailingClosure = true
    public private(set) var diagnostics: [Diagnostic]

    /// Thrown once the error is in `diagnostics`; the statement that failed is skipped.
    struct Failure: Error {}

    public init(_ source: String) {
        let (tokens, diagnostics) = Lexer.tokenize(source)
        self.tokens = tokens
        self.diagnostics = diagnostics
    }

    /// Parses `source`, with the lexer's and the parser's diagnostics in source order.
    public static func parse(_ source: String) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        var parser = Parser(source)
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

    private mutating func fail(_ message: String) -> Failure {
        // The lexer has reported an invalid token already.
        if current.kind != .invalid {
            diagnostics.append(.error("\(message), found \(describe(current))", at: current.range))
        }
        return Failure()
    }

    private mutating func unsupported(_ what: String, at range: SourceRange) -> Failure {
        diagnostics.append(.error("\(what) isn't supported yet", at: range))
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

    /// The lexer keeps `>` alone so that `List<List<Int>>` closes two argument lists; outside generic
    /// arguments, a `>` directly followed by `=` is `>=`.
    private var atGreaterEqual: Bool {
        current.isPunct(.greater) && peek().isPunct(.assign) && !peek().spaceBefore
    }

    /// Runs `body` with trailing closures allowed or not, and restores the setting after.
    private mutating func with<T, E: Error>(trailingClosures allowed: Bool,
                                            _ body: (inout Parser) throws(E) -> T) throws(E) -> T {
        let saved = allowsTrailingClosure
        allowsTrailingClosure = allowed
        defer { allowsTrailingClosure = saved }
        return try body(&self)
    }

    /// Runs `body` as a trial parse: if it fails, the parser goes back to where it was, and the errors it
    /// reported are dropped.
    private mutating func attempt<T>(_ body: (inout Parser) throws(Failure) -> T) -> T? {
        let savedPosition = position
        let savedDiagnostics = diagnostics.count
        do {
            return try body(&self)
        } catch {
            position = savedPosition
            diagnostics.removeSubrange(savedDiagnostics...)
            return nil
        }
    }

    // MARK: Lists and sequences

    /// After an opening bracket: items separated by commas, with an optional trailing comma, and the
    /// `closing` bracket.
    private mutating func parseList<T>(closing: Punct, _ context: String,
                                       _ item: (inout Parser) throws(Failure) -> T) throws(Failure) -> [T] {
        try with(trailingClosures: true) { parser throws(Failure) in
            var items: [T] = []
            while !parser.current.isPunct(closing) {
                items.append(try item(&parser))
                if !parser.consume(.comma) { break }
            }
            try parser.expect(closing, context)
            return items
        }
    }

    /// Whether the bracket just consumed closed a list that ended in a comma.
    private var closedAfterComma: Bool { position >= 2 && tokens[position - 2].isPunct(.comma) }

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
        var declarations: [Declaration] = []
        while true {
            declarations += parseSequence(of: "declaration") { parser throws(Failure) in try parser.parseDeclaration() }
            if atEnd { return SourceFile(declarations: declarations) }
            diagnostics.append(.error("unmatched '}'", at: current.range))
            advance()
        }
    }

    private mutating func parseDeclaration() throws(Failure) -> Declaration {
        if current.isKeyword(.struct) { return .structure(try parseStruct()) }
        if current.isKeyword(.func) { return .function(try parseFunction(selfConvention: nil)) }
        throw fail("expected 'struct' or 'func' to begin a declaration")
    }

    private mutating func parseStruct() throws(Failure) -> StructDecl {
        let start = advance().range
        let (name, nameRange) = try expectIdentifier("the struct's name")
        if current.isPunct(.less) { throw unsupported("a generic struct", at: current.range) }
        var decl = StructDecl(name: name, nameRange: nameRange, fields: [], conformances: [], methods: [],
                              deinitBody: nil, range: start)
        if consume(.lparen) {
            decl.fields = try parseList(closing: .rparen, "to close the struct's fields") { parser throws(Failure) in
                try parser.parseField()
            }
        }
        if consume(.colon) { decl.conformances = try parseConformances() }
        if consume(.lbrace) {
            parseMembers(into: &decl)
            try expect(.rbrace, "to close the struct's body")
        }
        decl.range = range(from: start)
        return decl
    }

    /// `('var' | 'let') identifier (':' type)? ('=' expression)?`, with a type, a default, or both.
    private mutating func parseField() throws(Failure) -> FieldDecl {
        let start = current.range
        let isVar: Bool
        if consume(.var) {
            isVar = true
        } else if consume(.let) {
            isVar = false
        } else {
            throw fail("expected 'var' or 'let' to begin a field")
        }
        let (name, _) = try expectIdentifier("the field's name")
        var type: TypeExpr?
        if consume(.colon) { type = try parseType() }
        var defaultValue: Expr?
        if consume(.assign) { defaultValue = try parseExpression() }
        if type == nil && defaultValue == nil { throw fail("expected ':' and a type, or '=' and a default") }
        return FieldDecl(isVar: isVar, name: name, type: type, defaultValue: defaultValue, range: range(from: start))
    }

    /// After the `:`: `'~'? identifier (',' '~'? identifier)*`.
    private mutating func parseConformances() throws(Failure) -> [Conformance] {
        var conformances: [Conformance] = []
        repeat {
            let negated = consume(.tilde)
            let (name, nameRange) = try expectIdentifier("a protocol name")
            conformances.append(Conformance(negated: negated, name: name, range: nameRange))
        } while consume(.comma)
        return conformances
    }

    private enum Member {
        case method(FuncDecl)
        case deinitializer(Block, keyword: SourceRange)
    }

    /// Adds the methods and the `deinit` between the struct body's braces to `decl`.
    private mutating func parseMembers(into decl: inout StructDecl) {
        let members = parseSequence(of: "declaration") { parser throws(Failure) in try parser.parseMember() }
        for member in members {
            switch member {
            case .method(let method):
                decl.methods.append(method)
            case .deinitializer(let body, let keyword):
                if decl.deinitBody != nil {
                    diagnostics.append(.error("a type declares at most one 'deinit'", at: keyword))
                }
                decl.deinitBody = body
            }
        }
    }

    private mutating func parseMember() throws(Failure) -> Member {
        if current.isKeyword(.deinit) {
            let keyword = advance().range
            return .deinitializer(try parseBlock(), keyword: keyword)
        }
        if consume(.mutating) { return .method(try parseFunction(selfConvention: .mutating)) }
        if consume(.consuming) { return .method(try parseFunction(selfConvention: .consuming)) }
        if current.isKeyword(.func) { return .method(try parseFunction(selfConvention: .borrowed)) }
        throw fail("expected a method or 'deinit'")
    }

    private mutating func parseFunction(selfConvention: SelfConvention?) throws(Failure) -> FuncDecl {
        guard current.isKeyword(.func) else { throw fail("expected 'func'") }
        let start = advance().range
        let (name, nameRange) = try expectIdentifier("the function's name")
        if current.isPunct(.less) { throw unsupported("a generic function", at: current.range) }
        try expect(.lparen, "to begin the parameters")
        let params = try parseList(closing: .rparen, "to close the parameters") { parser throws(Failure) in
            try parser.parseParam()
        }
        if current.isKeyword(.throws) { throw unsupported("'throws'", at: current.range) }
        var result: TypeExpr?
        if consume(.arrow) { result = try parseType() }
        if current.isKeyword(.where) { throw unsupported("a 'where' clause", at: current.range) }
        let body = try parseBlock()
        return FuncDecl(name: name, nameRange: nameRange, selfConvention: selfConvention, params: params,
                        result: result, body: body, range: range(from: start))
    }

    /// `(arg-label | '_')? identifier ':' param-convention? type`, where the label may be a keyword.
    private mutating func parseParam() throws(Failure) -> Param {
        let start = current.range
        let label: String?
        let name: String
        switch (current.kind, peek().kind) {
        case (.identifier(let first), .identifier(let second)):
            label = first == "_" ? nil : first
            name = second
            advance()
            advance()
        case (.keyword(let first), .identifier(let second)):
            label = first.rawValue
            name = second
            advance()
            advance()
        case (.identifier(let only), _):
            label = only
            name = only
            advance()
        default:
            throw fail("expected a parameter")
        }
        try expect(.colon, "before the parameter's type")
        let convention = parseConvention()
        let type = try parseType()
        if current.isPunct(.assign) { throw unsupported("a default argument", at: current.range) }
        return Param(label: label, name: name, convention: convention, type: type, range: range(from: start))
    }

    private mutating func parseConvention() -> ParamConvention? {
        if consume(.mutable) { return .mutable }
        if consume(.owned) { return .owned }
        return nil
    }

    // MARK: Types

    mutating func parseType() throws(Failure) -> TypeExpr {
        let start = current.range
        if consume(.some) {
            return .some(try parseType(), range: range(from: start))
        }
        if (current.isKeyword(.mutating) || current.isKeyword(.consuming)) && peek().isPunct(.lparen) {
            let kind: ClosureKind = advance().isKeyword(.mutating) ? .mutating : .consuming
            advance()
            let params = try parseFunctionTypeParams()
            try expect(.arrow, "after a function type's parameters")
            return .function(kind: kind, params: params, result: try parseType(), range: range(from: start))
        }
        if consume(.lbracket) { return try parseInlineArrayType(from: start) }
        if consume(.lparen) { return try parseParenthesizedType(from: start) }
        if current.isPunct(.star) { throw unsupported("a raw pointer type", at: current.range) }
        if current.isKeyword(.any) { throw unsupported("'any'", at: current.range) }
        let (name, _) = try expectIdentifier("a type")
        var arguments: [TypeExpr] = []
        if consume(.less) { arguments = try parseGenericArguments() }
        if current.isPunct(.question) { throw unsupported("an optional type", at: current.range) }
        return .named(name, arguments: arguments, range: range(from: start))
    }

    /// After the `[`: `int-literal 'of' type ']'`.
    private mutating func parseInlineArrayType(from start: SourceRange) throws(Failure) -> TypeExpr {
        guard case .intLiteral(let count) = current.kind, let size = Int(exactly: count) else {
            throw fail("expected the inline array's count")
        }
        advance()
        guard case .identifier("of") = current.kind else { throw fail("expected 'of' in an inline array type") }
        advance()
        let element = try parseType()
        try expect(.rbracket, "to close the inline array type")
        return .inlineArray(count: size, element: element, range: range(from: start))
    }

    /// After the `(`: a function type, `()`, or a single type in parentheses.
    private mutating func parseParenthesizedType(from start: SourceRange) throws(Failure) -> TypeExpr {
        let params = try parseFunctionTypeParams()
        if consume(.arrow) {
            return .function(kind: .plain, params: params, result: try parseType(), range: range(from: start))
        }
        if params.isEmpty { return .void(range: range(from: start)) }
        if params.count == 1, !params[0].keep, params[0].convention == nil, !closedAfterComma {
            return params[0].type
        }
        throw unsupported("a tuple type", at: range(from: start))
    }

    /// After the `<`: one or more types separated by commas, and the `>`.
    private mutating func parseGenericArguments() throws(Failure) -> [TypeExpr] {
        if current.isPunct(.greater) { throw fail("expected a type") }
        return try parseList(closing: .greater, "to close the generic arguments") { parser throws(Failure) in
            try parser.parseType()
        }
    }

    /// After the `(`: `fn-param-type (',' fn-param-type)* ','? ')'`.
    private mutating func parseFunctionTypeParams() throws(Failure) -> [FunctionTypeParam] {
        try parseList(closing: .rparen, "to close the parameter types") { parser throws(Failure) in
            var keep = false
            if case .identifier("keep") = parser.current.kind, parser.startsType(parser.peek()) {
                parser.advance()
                keep = true
            }
            let convention = parser.parseConvention()
            return FunctionTypeParam(keep: keep, convention: convention, type: try parser.parseType())
        }
    }

    private func startsType(_ token: Token) -> Bool {
        switch token.kind {
        case .identifier, .punct(.lparen), .punct(.lbracket), .keyword(.mutable), .keyword(.owned), .keyword(.some),
             .keyword(.mutating), .keyword(.consuming):
            return true
        default:
            return false
        }
    }

    // MARK: Statements

    private mutating func parseBlock() throws(Failure) -> Block {
        let start = try expect(.lbrace, "to begin a block").range
        let statements = parseStatements()
        try expect(.rbrace, "to close the block")
        return Block(statements: statements, range: range(from: start))
    }

    private mutating func parseStatements() -> [Stmt] {
        with(trailingClosures: true) { parser in
            parser.parseSequence(of: "statement") { parser throws(Failure) in try parser.parseStatement() }
        }
    }

    private mutating func parseStatement() throws(Failure) -> Stmt {
        let start = current.range
        let kind: StmtKind
        if current.isKeyword(.owned) || current.isKeyword(.let) || current.isKeyword(.var) {
            kind = .binding(try parseBinding())
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
        let (lower, upper) = try with(trailingClosures: false) { parser throws(Failure) in
            let lower = try parser.parseBinary(minimumLevel: 6)
            guard parser.consume(.halfOpenRange) else {
                throw parser.fail("expected '..<': the one loop supported so far is 'for i in a..<b'")
            }
            return (lower, try parser.parseBinary(minimumLevel: 6))
        }
        return .forRange(name: name, nameRange: nameRange, lower: lower, upper: upper, body: try parseBlock())
    }

    /// An expression, or an assignment to one.
    private mutating func parseExpressionStatement() throws(Failure) -> StmtKind {
        let target = try parseExpression()
        if case .closure = target.kind {
            diagnostics.append(.error("this closure would never run; 'do { … }' groups statements", at: target.range))
        }
        guard case .punct(let p) = current.kind, p.isAssignment else { return .expression(target) }
        guard let op = AssignOperator(rawValue: p.rawValue) else { throw unsupported("'\(p.rawValue)'", at: current.range) }
        advance()
        return .assign(target: target, op: op, value: try parseExpression())
    }

    /// The condition of an `if` or `while`, which the statement's block follows.
    private mutating func parseCondition() throws(Failure) -> Expr {
        if current.isKeyword(.let) || current.isKeyword(.var) || current.isKeyword(.case) {
            throw unsupported("a binding condition", at: current.range)
        }
        let condition = try with(trailingClosures: false) { parser throws(Failure) in try parser.parseExpression() }
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

    private mutating func parseBinding() throws(Failure) -> Binding {
        let owned = consume(.owned)
        let kind: BindingKind
        if consume(.let) {
            kind = .let
        } else if consume(.var) {
            kind = .var
        } else {
            throw fail("expected 'let' or 'var' after 'owned'")
        }
        let (name, nameRange) = try expectIdentifier("a name to bind")
        var type: TypeExpr?
        if consume(.colon) { type = try parseType() }
        var value: Expr?
        if consume(.assign) { value = try parseExpression() }
        if current.isPunct(.comma) { throw unsupported("more than one binding in a declaration", at: current.range) }
        return Binding(owned: owned, kind: kind, name: name, nameRange: nameRange, type: type, value: value)
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
            // A line that ends in a comparison '>' continues; the lexer can't tell it from a closing one.
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
        let make: ((Expr) -> ExprKind)?
        switch current.kind {
        case .punct(.minus): make = { .unary(.negate, $0) }
        case .punct(.bang): make = { .unary(.not, $0) }
        case .punct(.amp): make = { .lend($0) }
        case .keyword(.copy): make = { .copy($0) }
        case .keyword(.consume): make = { .consume($0) }
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
            } else if current.isPunct(.lbrace) && allowsTrailingClosure {
                expr = try appendingTrailingClosure(to: expr)
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

    /// Parses the closure at the current `{` as the last argument of `callee`'s call, which it makes if
    /// `callee` isn't a call already.
    private mutating func appendingTrailingClosure(to callee: Expr) throws(Failure) -> Expr {
        let closure = try parseClosure()
        let argument = Argument(label: nil, value: closure)
        let range = SourceRange(callee.range.start, closure.range.end)
        if case .call(let function, let arguments) = callee.kind {
            return Expr(id: callee.id, kind: .call(callee: function, arguments: arguments + [argument]), range: range)
        }
        return makeExpr(.call(callee: callee, arguments: [argument]), range)
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
            let typeArguments = genericArgumentsInExpression() ?? []
            return makeExpr(.name(name, typeArguments: typeArguments), range(from: start))
        case .punct(.lparen):
            advance()
            return try parseParenthesized(from: start)
        case .punct(.lbracket):
            advance()
            let elements = try parseList(closing: .rbracket, "to close the array literal") { parser throws(Failure) in
                try parser.parseExpression()
            }
            return makeExpr(.arrayLiteral(elements), range(from: start))
        case .punct(.lbrace):
            return try parseClosure()
        case .keyword(.if), .keyword(.when):
            throw unsupported("'\(current)' as an expression", at: current.range)
        default:
            throw fail("expected an expression")
        }
    }

    /// After the `(`: an expression in parentheses and the `)`.
    private mutating func parseParenthesized(from start: SourceRange) throws(Failure) -> Expr {
        if current.isPunct(.rparen) { throw unsupported("the empty tuple", at: SourceRange(start.start, current.range.end)) }
        let inner = try with(trailingClosures: true) { parser throws(Failure) in try parser.parseExpression() }
        if current.isPunct(.comma) { throw unsupported("a tuple", at: current.range) }
        try expect(.rparen, "to close the parenthesized expression")
        return Expr(id: inner.id, kind: inner.kind, range: range(from: start))
    }

    /// After a name, `<` begins generic arguments only when they parse and are followed by a token that
    /// can follow them, so `f(a < b, c > (d))` passes `a<b, c>(d)`. Otherwise it is a comparison.
    private mutating func genericArgumentsInExpression() -> [TypeExpr]? {
        guard current.isPunct(.less) else { return nil }
        return attempt { parser throws(Failure) in
            parser.advance()
            let arguments = try parser.parseGenericArguments()
            switch parser.current.kind {
            case .punct(.lparen), .punct(.dot), .punct(.rparen), .punct(.rbracket), .punct(.comma), .punct(.colon),
                 .punct(.semicolon), .punct(.question), .punct(.bang), .punct(.lbrace), .punct(.equal),
                 .punct(.notEqual), .punct(.andAnd), .punct(.orOr), .punct(.coalesce), .newline, .eof:
                return arguments
            default:
                throw Failure()
            }
        }
    }

    // MARK: Closures

    private struct ClosureSignature {
        var captures: [Capture] = []
        var params: [ClosureParam]?
        var result: TypeExpr?
    }

    private mutating func parseClosure() throws(Failure) -> Expr {
        let start = try expect(.lbrace, "to begin a closure").range
        let signature = attempt { parser throws(Failure) in try parser.parseClosureSignature() } ?? ClosureSignature()
        let statements = parseStatements()
        try expect(.rbrace, "to close the closure")
        let body = Block(statements: statements, range: range(from: start))
        let closure = ClosureExpr(captures: signature.captures, params: signature.params, result: signature.result,
                                  body: body)
        return makeExpr(.closure(closure), range(from: start))
    }

    /// `capture-list? closure-params? ('->' type)? 'in'`, with at least one part before `in`. It fails
    /// when the closure has no signature.
    private mutating func parseClosureSignature() throws(Failure) -> ClosureSignature {
        var signature = ClosureSignature()
        if consume(.lbracket) {
            if current.isPunct(.rbracket) { throw fail("expected 'move' or 'copy'") }
            signature.captures = try parseList(closing: .rbracket, "to close the capture list") { parser throws(Failure) in
                try parser.parseCapture()
            }
        }
        if consume(.lparen) {
            signature.params = try parseList(closing: .rparen, "to close the closure's parameters") { parser throws(Failure) in
                let param = try parser.parseParam()
                return ClosureParam(name: param.name, convention: param.convention, type: param.type, range: param.range)
            }
        } else if case .identifier = current.kind {
            var params: [ClosureParam] = []
            repeat {
                let (name, nameRange) = try expectIdentifier("a parameter name")
                params.append(ClosureParam(name: name, convention: nil, type: nil, range: nameRange))
            } while consume(.comma)
            signature.params = params
        }
        if consume(.arrow) { signature.result = try parseType() }
        guard consume(.in) else { throw fail("expected 'in' after the closure's signature") }
        return signature
    }

    /// `('move' | 'copy') (identifier | 'self')`.
    private mutating func parseCapture() throws(Failure) -> Capture {
        let start = current.range
        let mode: CaptureMode
        if case .identifier("move") = current.kind {
            mode = .move
        } else if current.isKeyword(.copy) {
            mode = .copy
        } else {
            throw fail("expected 'move' or 'copy'")
        }
        advance()
        let name = consume(.self) ? "self" : try expectIdentifier("a capture").0
        return Capture(mode: mode, name: name, range: range(from: start))
    }
}
