internal import RayoDiagnostics
internal import RayoSource

/// Parses the grammar's sequences of items: statements and declarations, one to a line or `;`, and the
/// arguments, parameters and fields a `(` opens, separated by commas.
extension Parser {
    /// Parses items separated by newlines or `;`, up to a `}` or the end of the file, which it leaves for the
    /// caller. An item that fails is skipped, and its error stays reported; `failed` gives what the sequence keeps in
    /// its place, from how it failed and the source it covers, or nil where it keeps nothing.
    mutating func parseLines<T, Failure: Error>(
        ifUnended unended: ErrorCase,
        _ item: (inout Parser) throws(Failure) -> T,
        ifFailed failed: (Failure, SourceRange) -> T?,
    ) -> [T] {
        var items: [T] = []
        skipSeparators()
        while !current.isPunct(.rbrace) && !atEnd {
            let start = current.range
            do {
                items.append(try item(&self))
                // An item that runs on past its end is kept, and the rest of it reported and skipped.
                if !atStatementEnd {
                    _ = fail(unended)
                    recover()
                }
            } catch {
                // An item that failed is skipped, up to its end, and kept as `failed` says. The item covers at least
                // its first token, which it either read or the skipping did.
                recover()
                if let kept = failed(error, range(from: start)) { items.append(kept) }
            }
            skipSeparators()
        }
        return items
    }

    /// After an opening bracket: parses items separated by commas, with an optional trailing comma, and `closing`, the
    /// bracket that closes it.
    mutating func parseList<T>(
        upTo closing: Punct, ifUnclosed unclosed: ErrorCase,
        _ item: (inout Parser) throws(ParseFailure) -> T,
    ) throws(ParseFailure) -> [T] {
        var items: [T] = []
        while !current.isPunct(closing) {
            items.append(try item(&self))
            // An item without a comma after it is the last.
            if !consume(.comma) { break }
        }
        try expect(closing, else: unclosed)
        return items
    }

    /// After the `(` of a declaration's header: parses its comma-separated parameters or fields into `items`, and the
    /// `)`. An item that fails is kept as a failed one, and the parser goes on to the next.
    mutating func parseHeaderList<T: Sendable>(
        into items: inout [FailedDecl.HeaderItem<T>], ifUnclosed unclosed: ErrorCase,
        _ item: (inout Parser) throws(ParseFailure) -> T,
    ) throws(ParseFailure) {
        while !current.isPunct(.rparen) {
            do {
                items.append(.parsed(try item(&self)))
            } catch {
                // A failed item is skipped up to the comma or `)` after it. Where it stops anywhere else, such as at
                // the `{` of a body, the list fails with the item's error alone.
                recover(upTo: [.comma, .rparen, .lbrace])
                items.append(.failed)
                guard current.isPunct(.comma) || current.isPunct(.rparen) else { throw error }
            }
            // An item without a comma after it is the last.
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: unclosed)
    }

    private mutating func skipSeparators() {
        while current.kind == .newline || current.isPunct(.semicolon) { advance() }
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it, the `}` after it, the end of the
    /// file, or one of `stops` outside the item's brackets.
    mutating func recover(upTo stops: [Punct] = []) {
        var depth = 0
        loop: while !atEnd {
            // A stop ends the item only outside its brackets.
            if depth == 0, case .punct(let punct) = current.kind, stops.contains(punct) { break }
            switch current.kind {
            // A bracket the item opens is skipped whole, up to the bracket that closes it.
            case .punct(.lbrace), .punct(.lparen), .punct(.lbracket):
                depth += 1

            // A `}` outside the item's brackets closes its block, which the sequence stops at; inside, it closes one.
            case .punct(.rbrace):
                if depth == 0 { break loop }
                depth -= 1

            // A `)` or `]` closes one of the item's brackets; a stray one is skipped.
            case .punct(.rparen), .punct(.rbracket):
                if depth > 0 { depth -= 1 }

            // A newline or `;` outside the item's brackets ends it; inside them, it is skipped.
            case .newline, .punct(.semicolon):
                if depth == 0 { break loop }

            // Every other token is skipped.
            default:
                break
            }
            advance()
        }
    }
}
