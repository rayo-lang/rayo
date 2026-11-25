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
            if atEnd { return SourceFile(declarations: declarations, source: bytes, tokens: tokens) }

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
            // A declaration that failed is kept with what the parser read of it; text that began none keeps nothing.
            failure.parts.map {
                .failed(FailedDecl(name: failure.name, nameRange: failure.nameRange, parts: $0, range: range))
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

    /// After the `func`: `identifier '(' parameters ')' ('->' type)? block`. A function whose header fails still has
    /// its body parsed, where a `{` comes next, and throws what it read.
    private mutating func parseFunction() throws(DeclarationFailure) -> FuncDecl {
        let header = parseFunctionHeader()

        // After a header whose rest was skipped, only a `{` begins the body. A body that fails is reported, and kept
        // as none.
        let body: Block? = if header.readToEnd || current.isPunct(.lbrace) { try? parseBlock() } else { nil }

        guard let function = header.declaration(body: body) else { throw header.failure(body: body) }
        return function
    }

    /// Reads a function's header, up to its body. A parameter that fails is kept as a failed one, and any other error
    /// skips the rest of the header, up to the `{` of a body.
    private mutating func parseFunctionHeader() -> FunctionHeader {
        var header = FunctionHeader()
        do throws(ParseFailure) {
            header.name = try expectIdentifier(else: ErrorCode.missingFunctionName)
            try expect(.lparen, else: ErrorCode.missingParameterList)
            try parseHeaderList(into: &header.parameters, ifUnclosed: ErrorCode.unclosedParameters) {
                parser throws(ParseFailure) in
                try parser.parseParameter()
            }
            header.result = consume(.arrow) ? try parseType() : nil
            header.readToEnd = true
        } catch {
            skipHeader()
        }
        return header
    }

    /// `(label | '_')? identifier ':' ('mutable'? '&')? type ('=' expression)?`, where a label may be a keyword.
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

    /// `&` or `mutable &`, before a parameter's type, when one is written.
    private mutating func parseConvention() -> ParamConvention? {
        if consume(.ampersand) { return .borrowed }
        // A `mutable` without a `&` after it is left to be reported where a type is expected.
        if current.isKeyword(.mutable), peek().isPunct(.ampersand) {
            advance()
            advance()
            return .mutable
        }
        // Any other token starts the type.
        return nil
    }

    /// After the `struct`: `identifier ('(' fields ')')? ('{' declarations '}')?`. A struct whose header fails still
    /// has its body parsed, where a `{` comes next, and throws what it read.
    private mutating func parseStruct() throws(DeclarationFailure) -> StructDecl {
        let header = parseStructHeader()

        // A struct may leave its body out. A body that fails is reported, and kept as none.
        let members: [Declaration]? = if current.isPunct(.lbrace) { try? parseStructBody() } else { [] }

        guard let structure = header.declaration(members: members) else { throw header.failure(members: members) }
        return structure
    }

    /// Reads a struct's header, up to its body. A field that fails is kept as a failed one, and any other error skips
    /// the rest of the header, up to the `{` of a body.
    private mutating func parseStructHeader() -> StructHeader {
        var header = StructHeader()
        do throws(ParseFailure) {
            header.name = try expectIdentifier(else: ErrorCode.missingStructName)
            // A struct may leave its fields out.
            if consume(.lparen) {
                try parseHeaderList(into: &header.fields, ifUnclosed: ErrorCode.unclosedFields) {
                    parser throws(ParseFailure) in
                    try parser.parseField()
                }
            }
            header.readToEnd = true
        } catch {
            skipHeader()
        }
        return header
    }

    /// At the `{` of a struct's body: `'{' declarations '}'`, the body and its members.
    private mutating func parseStructBody() throws(ParseFailure) -> [Declaration] {
        try parseNested(.structBody) { parser throws(ParseFailure) in
            parser.advance()
            let members = parser.parseDeclarations()
            try parser.expect(.rbrace, else: ErrorCode.unclosedStructBody)
            return members
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

/// What the parser read of a function's header, from its name to its result type.
private struct FunctionHeader {
    var name: (text: String, range: SourceRange)?
    var parameters: [HeaderItem<Param>] = []
    var result: TypeExpr?
    /// Whether the parser read the header to its end, rather than skipping the rest of it after an error.
    var readToEnd = false

    /// The function that the header and `body` declare, or nil where any part of either failed.
    func declaration(body: Block?) -> FuncDecl? {
        guard readToEnd, let name, let body, let parameters = parameters.allParsed() else { return nil }
        return FuncDecl(name: name.text, nameRange: name.range, parameters: parameters, result: result, body: body)
    }

    /// The failure of a function whose header or `body` failed, with what the parser read of them.
    func failure(body: Block?) -> DeclarationFailure {
        let parts = FailedDeclParts.function(parameters: parameters, result: result, body: body)
        return DeclarationFailure(parts: parts, name: name?.text, nameRange: name?.range)
    }
}

/// What the parser read of a struct's header: its name and its fields.
private struct StructHeader {
    var name: (text: String, range: SourceRange)?
    var fields: [HeaderItem<FieldDecl>] = []
    /// Whether the parser read the header to its end, rather than skipping the rest of it after an error.
    var readToEnd = false

    /// The struct that the header and `members` declare, or nil where any part of either failed.
    func declaration(members: [Declaration]?) -> StructDecl? {
        guard readToEnd, let name, let members, let fields = fields.allParsed() else { return nil }
        return StructDecl(name: name.text, nameRange: name.range, fields: fields, members: members)
    }

    /// The failure of a struct whose header or body failed, with what the parser read of them.
    func failure(members: [Declaration]?) -> DeclarationFailure {
        let parts = FailedDeclParts.structure(fields: fields, members: members ?? [])
        return DeclarationFailure(parts: parts, name: name?.text, nameRange: name?.range)
    }
}

private extension Array {
    /// The items of a header's list, or nil where any of them failed.
    func allParsed<Item>() -> [Item]? where Element == HeaderItem<Item> {
        var parsed: [Item] = []
        for element in self {
            guard case .parsed(let item) = element else { return nil }
            parsed.append(item)
        }
        return parsed
    }
}
