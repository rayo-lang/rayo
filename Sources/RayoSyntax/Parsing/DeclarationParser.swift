import RayoDiagnostics

/// Parses a file's declarations, and the parameters of its functions.
struct DeclarationParser {
    let tokens: TokenStream

    func parseFile() -> SourceFile {
        var functions: [FuncDecl] = []
        while true {
            functions += tokens.parseSequence(ifUnended: ErrorCode.unendedDeclaration) { () throws(ParseFailure) in
                try parseFunction()
            }
            // The declarations run to the end of the file.
            if tokens.atEnd { return SourceFile(functions: functions) }

            // A `}` that closes no block ends the sequence early; it is reported, and the declarations go on after it.
            tokens.report(.unmatchedBrace)
            tokens.advance()
        }
    }

    /// `'func' identifier '(' parameters ')' ('->' type)? block`.
    private func parseFunction() throws(ParseFailure) -> FuncDecl {
        // Every declaration starts with `func`.
        guard tokens.consume(.func) else { throw tokens.fail(ErrorCode.missingFunc) }
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
}
