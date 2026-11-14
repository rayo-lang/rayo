internal import RayoDiagnostics
internal import RayoSource

/// Parses a file's declarations: its functions with their parameters, and its structs with their fields.
extension Parser {
    mutating func parseFile() -> SourceFile {
        var declarations: [Declaration] = []
        while true {
            // Parse declarations up to the end of the file or a `}` that closes no block.
            declarations += parseLines(ifUnended: ErrorCode.unendedDeclaration) { parser throws(DeclarationFailure) in
                try parser.parseDeclaration()
            } ifFailed: { failure, range in
                // A declaration that failed is kept as a failed one of its kind; text that began none keeps nothing.
                failure.kind.map {
                    .failed(FailedDecl(kind: $0, name: failure.name, nameRange: failure.nameRange, range: range))
                }
            }
            // The declarations run to the end of the file.
            if atEnd { return SourceFile(declarations) }

            // A `}` that closes no block ends the sequence early; it is reported, and the declarations go on after it.
            report(.unmatchedBrace)
            advance()
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
        var name: (String, SourceRange)?
        do throws(ParseFailure) {
            let (readName, nameRange) = try expectIdentifier(else: ErrorCode.missingFunctionName)
            name = (readName, nameRange)
            try expect(.lparen, else: ErrorCode.missingParameterList)
            let parameters = try parseList(ifUnclosed: ErrorCode.unclosedParameters) { parser throws(ParseFailure) in
                try parser.parseParameter()
            }
            let result = consume(.arrow) ? try parseType() : nil
            let body = try parseBlock()
            return FuncDecl(name: readName, nameRange: nameRange, parameters: parameters, result: result, body: body)
        } catch {
            throw DeclarationFailure(kind: .function, name: name?.0, nameRange: name?.1)
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

    /// `mutable` or `owned`, which are names everywhere but before a parameter's type.
    private mutating func parseConvention() -> ParamConvention? {
        // Any other token starts the type.
        guard case .identifier(let word) = current.kind, let convention = ParamConvention(rawValue: word) else {
            return nil
        }
        // Without a type after it, the word is the type's name.
        guard startsType(peek()) else { return nil }

        // A type after the word makes the word the parameter's convention.
        advance()
        return convention
    }

    /// After the `struct`: `identifier ('(' fields ')')? ('{' '}')?`. A struct that fails throws its name, where it
    /// read it.
    private mutating func parseStruct() throws(DeclarationFailure) -> StructDecl {
        var name: (String, SourceRange)?
        do throws(ParseFailure) {
            // Read the name, and the fields where the header has them.
            let (readName, nameRange) = try expectIdentifier(else: ErrorCode.missingStructName)
            name = (readName, nameRange)
            let fields = consume(.lparen) ? try parseFields() : []

            // A struct may leave its body out.
            if consume(.lbrace) { try parseEmptyBody() }
            return StructDecl(name: readName, nameRange: nameRange, fields: fields)
        } catch {
            throw DeclarationFailure(kind: .structure, name: name?.0, nameRange: name?.1)
        }
    }

    /// After the `{` of a struct's body: the `}` that closes it. Each item in the body, which holds nothing, is
    /// reported.
    private mutating func parseEmptyBody() throws(ParseFailure) {
        // Each item fails, so the sequence reports it and skips it up to the next.
        let _: [Never] = parseLines(ifUnended: ErrorCode.unclosedStructBody) { parser throws(ParseFailure) in
            throw parser.fail(ErrorCode.unclosedStructBody)
        } ifFailed: { _, _ in
            nil
        }
        try expect(.rbrace, else: ErrorCode.unclosedStructBody)
    }

    /// After the `(` of a struct's header: its fields and the `)`.
    private mutating func parseFields() throws(ParseFailure) -> [FieldDecl] {
        try parseList(ifUnclosed: ErrorCode.unclosedFields) { parser throws(ParseFailure) in try parser.parseField() }
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

/// A declaration at a file's top level.
private enum Declaration {
    case function(FuncDecl)
    case structure(StructDecl)
    case failed(FailedDecl)

    /// The function the declaration declares, if it declares one.
    var function: FuncDecl? {
        if case .function(let function) = self { function } else { nil }
    }

    /// The struct the declaration declares, if it declares one.
    var structure: StructDecl? {
        if case .structure(let structure) = self { structure } else { nil }
    }

    /// The declaration, if it failed to parse.
    var failed: FailedDecl? {
        if case .failed(let failed) = self { failed } else { nil }
    }
}

private extension SourceFile {
    /// The file that `declarations` make, each kind in source order.
    init(_ declarations: [Declaration]) {
        self.init(
            functions: declarations.compactMap(\.function), structs: declarations.compactMap(\.structure),
            failedDeclarations: declarations.compactMap(\.failed),
        )
    }
}
