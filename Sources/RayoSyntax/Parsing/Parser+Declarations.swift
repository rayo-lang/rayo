import RayoDiagnostics

/// Parses a file's declarations: its functions with their parameters, and its structs with their fields.
extension Parser {
    func parseFile() -> SourceFile {
        var declarations: [Declaration] = []
        while true {
            // Parse declarations up to the end of the file or a `}` that closes no block.
            declarations += parseLines(ifUnended: ErrorCode.unendedDeclaration) {
                () throws(ParseFailure) in try parseDeclaration()
            }
            // The declarations run to the end of the file.
            if atEnd { return SourceFile(declarations) }

            // A `}` that closes no block ends the sequence early; it is reported, and the declarations go on after it.
            report(.unmatchedBrace)
            advance()
        }
    }

    /// `'func' …` or `'struct' …`.
    private func parseDeclaration() throws(ParseFailure) -> Declaration {
        if consume(.func) {
            // A `func` is followed by a function's name, parameters, result and body.
            .function(try parseFunction())
        } else if consume(.struct) {
            // A `struct` is followed by a struct's name, its header of fields, and its body.
            .structure(try parseStruct())
        } else {
            // Any other token begins no declaration.
            throw fail(ErrorCode.missingDeclaration)
        }
    }

    /// After the `func`: `identifier '(' parameters ')' ('->' type)? block`.
    private func parseFunction() throws(ParseFailure) -> FuncDecl {
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingFunctionName)
        try expect(.lparen, else: ErrorCode.missingParameterList)
        let parameters = try parseList(ifUnclosed: ErrorCode.unclosedParameters) {
            () throws(ParseFailure) in try parseParameter()
        }
        let result = consume(.arrow) ? try parseType() : nil
        let body = try parseBlock()
        return FuncDecl(name: name, nameRange: nameRange, parameters: parameters, result: result, body: body)
    }

    /// `(label | '_')? identifier ':' ('mutable' | 'owned')? type ('=' expression)?`, where a label may be a
    /// keyword.
    private func parseParameter() throws(ParseFailure) -> Param {
        // Read the parameter's parts in order; a label, convention or default value left out reads as nil.
        let start = current.range
        let writtenLabel = parseWrittenLabel()
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingParameterName)
        // Every parameter has a type.
        guard consume(.colon) else { throw fail(ErrorCode.missingParameterType) }
        let convention = parseConvention()
        let type = try parseType()
        let defaultValue = consume(.assign) ? try parseExpression() : nil

        // Without a written label, the name is the label, and a label of `_` leaves the parameter unlabeled.
        let labelSpelling = writtenLabel ?? name
        let label = labelSpelling == "_" ? nil : labelSpelling
        return Param(label: label, name: name, nameRange: nameRange, convention: convention,
                     type: type, defaultValue: defaultValue, range: range(from: start))
    }

    /// Parses the label written before a parameter's name, `_` included, when one is.
    private func parseWrittenLabel() -> String? {
        // Anything but a word with a name after it is no label.
        guard let spelling = current.labelSpelling, case .identifier = peek().kind else { return nil }
        advance()
        return spelling
    }

    /// `mutable` or `owned`, which are names everywhere but before a parameter's type.
    private func parseConvention() -> ParamConvention? {
        // Any other token starts the type.
        guard case .identifier(let word) = current.kind, let convention = ParamConvention(rawValue: word) else {
            return nil
        }
        switch peek().kind {
        // A type after the word makes the word the parameter's convention.
        case .identifier, .punct(.lparen):
            advance()
            return convention

        // Without a type after it, the word is the type's name.
        default:
            return nil
        }
    }

    /// After the `struct`: `identifier ('(' fields ')')? ('{' '}')?`.
    private func parseStruct() throws(ParseFailure) -> StructDecl {
        // Read the name, and the fields where the header has them.
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingStructName)
        let fields = consume(.lparen) ? try parseFields() : []

        // A struct may leave its body out.
        if consume(.lbrace) { try parseEmptyBody() }
        return StructDecl(name: name, nameRange: nameRange, fields: fields)
    }

    /// After the `{` of a struct's body: the `}` that closes it. Each item in the body, which holds nothing, is
    /// reported.
    private func parseEmptyBody() throws(ParseFailure) {
        // Each item fails, so the sequence reports it and skips it up to the next.
        let _: [Never] = parseLines(ifUnended: ErrorCode.unclosedStructBody) {
            () throws(ParseFailure) in throw fail(ErrorCode.unclosedStructBody)
        }
        try expect(.rbrace, else: ErrorCode.unclosedStructBody)
    }

    /// After the `(` of a struct's header: its fields and the `)`.
    private func parseFields() throws(ParseFailure) -> [FieldDecl] {
        try parseList(ifUnclosed: ErrorCode.unclosedFields) { () throws(ParseFailure) in try parseField() }
    }

    /// `('var' | 'let') identifier (':' type)? ('=' expression)?`.
    private func parseField() throws(ParseFailure) -> FieldDecl {
        // Read the field's parts in order; a type or default value left out reads as nil.
        let kind = try parseFieldKind()
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingFieldName)
        let type = consume(.colon) ? try parseType() : nil
        let defaultValue = consume(.assign) ? try parseExpression() : nil

        return FieldDecl(kind: kind, name: name, nameRange: nameRange, type: type, defaultValue: defaultValue)
    }

    /// `'var'` or `'let'`, which begins a field.
    private func parseFieldKind() throws(ParseFailure) -> BindingKind {
        if consume(.var) {
            // A `var` field can change.
            .var
        } else if consume(.let) {
            // A `let` field can't.
            .let
        } else {
            // Any other token begins no field.
            throw fail(ErrorCode.missingFieldKind)
        }
    }
}

/// A declaration at a file's top level.
private enum Declaration {
    case function(FuncDecl)
    case structure(StructDecl)

    /// The function the declaration declares, if it declares one.
    var function: FuncDecl? {
        if case .function(let function) = self { function } else { nil }
    }

    /// The struct the declaration declares, if it declares one.
    var structure: StructDecl? {
        if case .structure(let structure) = self { structure } else { nil }
    }
}

private extension SourceFile {
    /// The file that `declarations` make, each kind in source order.
    init(_ declarations: [Declaration]) {
        self.init(functions: declarations.compactMap(\.function), structs: declarations.compactMap(\.structure))
    }
}
