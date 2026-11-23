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
        into items: inout [HeaderItem<T>], ifUnclosed unclosed: ErrorCase,
        _ item: (inout Parser) throws(ParseFailure) -> T,
    ) throws(ParseFailure) {
        while !current.isPunct(.rparen) {
            let start = position
            do {
                items.append(.parsed(try item(&self)))
            } catch {
                // A failed item is skipped up to the comma or `)` after it, outside the brackets it opened. Where it
                // stops anywhere else, such as at the `{` of a body, the list fails with the item's error alone.
                recover(upTo: [.comma, .rparen, .lbrace], insideBrackets: bracketsLeftOpen(since: start))
                items.append(.failed)
                guard current.isPunct(.comma) || current.isPunct(.rparen) else { throw error }
            }
            // An item without a comma after it is the last.
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: unclosed)
    }

    /// Skips the rest of a declaration's header that failed, up to the `{` of a body. Where a `)` at this level comes
    /// first, the skip goes past it, so a `{` inside the header's list isn't taken for the body.
    mutating func skipHeader() {
        if let ahead = closingParenthesisAhead() {
            for _ in 0...ahead { advance() }
        }
        recover(upTo: [.lbrace])
    }

    private mutating func skipSeparators() {
        while current.kind == .newline || current.isPunct(.semicolon) { advance() }
    }

    /// How many tokens past the current one the `)` at its level comes, or nil where the declaration ends first.
    private func closingParenthesisAhead() -> Int? {
        var depth = 0
        var ahead = 0
        while true {
            switch peek(ahead).kind {
            case .eof:
                return nil

            // A `)` outside the brackets ahead closes the one the parser is in.
            case .punct(.rparen) where depth == 0:
                return ahead

            case .punct(.lparen), .punct(.lbrace), .punct(.lbracket):
                depth += 1

            // A `}` outside the brackets ahead closes the declaration's block.
            case .punct(.rbrace):
                guard depth > 0 else { return nil }
                depth -= 1

            // A `)` or `]` closes one of the brackets ahead; a stray `]` closes nothing.
            case .punct(.rparen), .punct(.rbracket):
                depth = max(depth - 1, 0)

            // A newline or `;` outside the brackets ahead ends the declaration.
            case .newline, .punct(.semicolon):
                if depth == 0 { return nil }

            default:
                break
            }
            ahead += 1
        }
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it, the `}` after it, the end of the
    /// file, or one of `stops` outside the item's brackets. `open` counts those it opened before it failed.
    mutating func recover(upTo stops: [Punct] = [], insideBrackets open: Int = 0) {
        var depth = open
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
