import RayoDiagnostics

/// Parses a file's declarations: its functions with their parameters, and its structs with their fields.
struct DeclarationParser {
    let tokens: TokenStream

    func parseFile() -> SourceFile {
        var declarations: [Declaration] = []
        while true {
            declarations += tokens.parseSequence(ifUnended: ErrorCode.unendedDeclaration) { () throws(ParseFailure) in
                try parseDeclaration()
            }
            // The declarations run to the end of the file.
            if tokens.atEnd { return SourceFile(declarations) }

            // A `}` that closes no block ends the sequence early; it is reported, and the declarations go on after it.
            tokens.report(.unmatchedBrace)
            tokens.advance()
        }
    }

    /// `'func' …` or `'struct' …`.
    private func parseDeclaration() throws(ParseFailure) -> Declaration {
        // A `func` begins a function,
        if tokens.consume(.func) { return .function(try parseFunction()) }
        // and a `struct` a struct.
        if tokens.consume(.struct) { return .structure(try parseStruct()) }
        // Any other token begins no declaration.
        throw tokens.fail(ErrorCode.missingDeclaration)
    }

    /// After the `func`: `identifier '(' parameters ')' ('->' type)? block`.
    private func parseFunction() throws(ParseFailure) -> FuncDecl {
        let (name, nameRange) = try tokens.expectIdentifier(else: ErrorCode.missingFunctionName)
        try tokens.expect(.lparen, else: ErrorCode.missingParameterList)
        let parameters = try tokens.parseList(ifUnclosed: ErrorCode.unclosedParameters) { () throws(ParseFailure) in
            try parseParameter()
        }
        let result = tokens.consume(.arrow) ? try TypeParser(tokens: tokens).parseType() : nil
        let body = try StatementParser(tokens: tokens).parseBlock()
        return FuncDecl(name: name, nameRange: nameRange, parameters: parameters, result: result, body: body)
    }

    /// `(label | '_')? identifier ':' ('mutable' | 'owned')? type ('=' expression)?`, where a label may be a
    /// keyword.
    private func parseParameter() throws(ParseFailure) -> Param {
        // Read the parameter's parts in the order the declaration writes them.
        let start = tokens.current.range
        let writtenLabel = parseWrittenLabel()
        let (name, nameRange) = try tokens.expectIdentifier(else: ErrorCode.missingParameterName)
        // Every parameter has a type.
        guard tokens.consume(.colon) else { throw tokens.fail(ErrorCode.missingParameterType) }
        let convention = parseConvention()
        let type = try TypeParser(tokens: tokens).parseType()
        let defaultValue = try parseDefaultValue()

        // Without a written label, the name is the label; `_` in either place leaves the parameter unlabeled.
        let labelSpelling = writtenLabel ?? name
        let label = labelSpelling == "_" ? nil : labelSpelling
        return Param(label: label, name: name, nameRange: nameRange, convention: convention,
                     type: type, defaultValue: defaultValue, range: tokens.range(from: start))
    }

    /// Parses the label written before a parameter's name, `_` included, when one is.
    private func parseWrittenLabel() -> String? {
        // A word that no name follows is the name itself.
        guard let spelling = tokens.current.labelSpelling, case .identifier = tokens.peek().kind else { return nil }
        tokens.advance()
        return spelling
    }

    /// `('=' expression)?`, after a parameter's type.
    private func parseDefaultValue() throws(ParseFailure) -> Expr? {
        // A parameter without an `=` has no default.
        guard tokens.consume(.assign) else { return nil }
        return try ExpressionParser(tokens: tokens).parseExpression()
    }

    /// `mutable` or `owned`, which are names everywhere but before a parameter's type.
    private func parseConvention() -> ParamConvention? {
        // Any other word is the type.
        guard case .identifier(let word) = tokens.current.kind, let convention = ParamConvention(rawValue: word) else {
            return nil
        }
        switch tokens.peek().kind {
        // A type after the word makes the word the parameter's convention.
        case .identifier, .punct(.lparen):
            tokens.advance()
            return convention

        // Without a type after it, the word is the type's name.
        default:
            return nil
        }
    }

    /// After the `struct`: `identifier ('(' fields ')')? ('{' '}')?`.
    private func parseStruct() throws(ParseFailure) -> StructDecl {
        let (name, nameRange) = try tokens.expectIdentifier(else: ErrorCode.missingStructName)
        let fields = tokens.consume(.lparen) ? try parseFields() : []
        // A struct may leave its body out.
        if tokens.consume(.lbrace) { try parseEmptyBody() }
        return StructDecl(name: name, nameRange: nameRange, fields: fields)
    }

    /// After the `{` of a struct's body: the `}` that closes it. Each item in the body, which holds nothing, is
    /// reported.
    private func parseEmptyBody() throws(ParseFailure) {
        // Each item fails, so the sequence reports it and skips it up to the next.
        let _: [Never] = tokens.parseSequence(ifUnended: ErrorCode.unclosedStructBody) { () throws(ParseFailure) in
            throw tokens.fail(ErrorCode.unclosedStructBody)
        }
        try tokens.expect(.rbrace, else: ErrorCode.unclosedStructBody)
    }

    /// After the `(` of a struct's header: its fields and the `)`.
    private func parseFields() throws(ParseFailure) -> [FieldDecl] {
        try tokens.parseList(ifUnclosed: ErrorCode.unclosedFields) { () throws(ParseFailure) in
            try parseField()
        }
    }

    /// `('var' | 'let') identifier (':' type)?`.
    private func parseField() throws(ParseFailure) -> FieldDecl {
        let kind = try parseFieldKind()
        let (name, nameRange) = try tokens.expectIdentifier(else: ErrorCode.missingFieldName)
        let type = tokens.consume(.colon) ? try TypeParser(tokens: tokens).parseType() : nil
        return FieldDecl(kind: kind, name: name, nameRange: nameRange, type: type)
    }

    /// `'var'` or `'let'`, which begins a field.
    private func parseFieldKind() throws(ParseFailure) -> BindingKind {
        // A `var` field can change,
        if tokens.consume(.var) { return .var }
        // and a `let` one can't.
        if tokens.consume(.let) { return .let }
        // Any other token begins no field.
        throw tokens.fail(ErrorCode.missingFieldKind)
    }
}

/// A declaration at a file's top level.
private enum Declaration {
    case function(FuncDecl)
    case structure(StructDecl)
}

private extension SourceFile {
    /// The file that `declarations` make, each kind in source order.
    init(_ declarations: [Declaration]) {
        var functions: [FuncDecl] = []
        var structs: [StructDecl] = []
        for declaration in declarations {
            switch declaration {
            case .function(let function): functions.append(function)
            case .structure(let structure): structs.append(structure)
            }
        }
        self.init(functions: functions, structs: structs)
    }
}
