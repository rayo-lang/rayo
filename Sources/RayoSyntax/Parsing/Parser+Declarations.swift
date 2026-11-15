internal import RayoDiagnostics
internal import RayoSource

/// Parses declarations: functions with their parameters, and structs with their fields and members.
extension Parser {
    mutating func parseFile() -> SourceFile {
        var declarations: [Declaration] = []
        while true {
            // Parse declarations up to the end of the file or a `}` that closes no block.
            declarations += parseDeclarations()
            // The declarations run to the end of the file.
            if atEnd { return SourceFile(declarations: declarations) }

            // A `}` that closes no block ends the sequence early; it is reported, and the declarations go on after it.
            report(.unmatchedBrace)
            advance()
        }
    }

    /// Parses declarations, one to a line, up to the end of the file or a `}`.
    private mutating func parseDeclarations() -> [Declaration] {
        parseLines(ifUnended: ErrorCode.unendedDeclaration) { parser throws(DeclarationFailure) in
            try parser.parseDeclaration()
        } ifFailed: { failure, range in
            // A declaration that failed is kept as a failed one of its kind; text that began none keeps nothing.
            failure.kind.map {
                .failed(FailedDecl(kind: $0, name: failure.name, nameRange: failure.nameRange, range: range))
            }
        }
    }

    /// `'func' …` or `'struct' …`.
    private mutating func parseDeclaration() throws(DeclarationFailure) -> Declaration {
        if consume(.func) {
            // A `func` is followed by a function's name, parameters, result and body.
            .function(try parseFunction())
        } else if consume(.struct) {
            // A `struct` is followed by a struct's name, its header of fields, and its body.
            .structure(try parseStruct())
        } else {
            // Any other token begins no declaration.
            _ = fail(ErrorCode.missingDeclaration)
            throw DeclarationFailure()
        }
    }

    /// After the `func`: `identifier '(' parameters ')' ('->' type)? block`. A function that fails throws its name,
    /// where it read it.
    private mutating func parseFunction() throws(DeclarationFailure) -> FuncDecl {
        var name: (text: String, range: SourceRange)?
        do throws(ParseFailure) {
            let (readName, nameRange) = try expectIdentifier(else: ErrorCode.missingFunctionName)
            name = (readName, nameRange)
            try expect(.lparen, else: ErrorCode.missingParameterList)
            let parameters = try parseList(upTo: .rparen, ifUnclosed: ErrorCode.unclosedParameters) {
                parser throws(ParseFailure) in
                try parser.parseParameter()
            }
            let result = consume(.arrow) ? try parseType() : nil
            let body = try parseBlock()
            return FuncDecl(name: readName, nameRange: nameRange, parameters: parameters, result: result, body: body)
        } catch {
            throw DeclarationFailure(kind: .function, name: name?.text, nameRange: name?.range)
        }
    }

    /// `(label | '_')? identifier ':' ('mutable' | 'owned')? type ('=' expression)?`, where a label may be a
    /// keyword.
    private mutating func parseParameter() throws(ParseFailure) -> Param {
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
        return Param(
            label: label, name: name, nameRange: nameRange, convention: convention,
            type: type, defaultValue: defaultValue, range: range(from: start),
        )
    }

    /// Parses the label written before a parameter's name, `_` included, when one is.
    private mutating func parseWrittenLabel() -> String? {
        // Anything but a word with a name after it is no label.
        guard let spelling = current.labelSpelling, case .identifier = peek().kind else { return nil }
        advance()
        return spelling
    }

    /// `mutable` or `owned`, before a parameter's type, when one is written.
    private mutating func parseConvention() -> ParamConvention? {
        if consume(.mutable) { return .mutable }
        if consume(.owned) { return .owned }
        // Any other token starts the type.
        return nil
    }

    /// After the `struct`: `identifier ('(' fields ')')? ('{' declarations '}')?`. A struct that fails throws its name,
    /// where it read it.
    private mutating func parseStruct() throws(DeclarationFailure) -> StructDecl {
        var name: (text: String, range: SourceRange)?
        do throws(ParseFailure) {
            // Read the name, and the fields where the header has them.
            let (readName, nameRange) = try expectIdentifier(else: ErrorCode.missingStructName)
            name = (readName, nameRange)
            let fields = consume(.lparen) ? try parseFields() : []

            // A struct may leave its body out.
            let members = consume(.lbrace) ? try parseMembers() : []
            return StructDecl(name: readName, nameRange: nameRange, fields: fields, members: members)
        } catch {
            throw DeclarationFailure(kind: .structure, name: name?.text, nameRange: name?.range)
        }
    }

    /// After the `{` of a struct's body: its members, which are declarations, and the `}` that closes it.
    private mutating func parseMembers() throws(ParseFailure) -> [Declaration] {
        let members = parseDeclarations()
        try expect(.rbrace, else: ErrorCode.unclosedStructBody)
        return members
    }

    /// After the `(` of a struct's header: its fields and the `)`.
    private mutating func parseFields() throws(ParseFailure) -> [FieldDecl] {
        try parseList(upTo: .rparen, ifUnclosed: ErrorCode.unclosedFields) { parser throws(ParseFailure) in
            try parser.parseField()
        }
    }

    /// `('var' | 'let') identifier (':' type)? ('=' expression)?`.
    private mutating func parseField() throws(ParseFailure) -> FieldDecl {
        // Read the field's parts in order; a type or default value left out reads as nil.
        let kind = try parseFieldKind()
        let (name, nameRange) = try expectIdentifier(else: ErrorCode.missingFieldName)
        let type = consume(.colon) ? try parseType() : nil
        let defaultValue = consume(.assign) ? try parseExpression() : nil

        return FieldDecl(kind: kind, name: name, nameRange: nameRange, type: type, defaultValue: defaultValue)
    }

    /// `'var'` or `'let'`, which begins a field.
    private mutating func parseFieldKind() throws(ParseFailure) -> BindingKind {
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
