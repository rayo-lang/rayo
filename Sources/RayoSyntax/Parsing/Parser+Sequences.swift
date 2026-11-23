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
                skipFailedItem(openedSince: start)
                items.append(.failed)
                guard current.isPunct(.comma) || current.isPunct(.rparen) else { throw error }
            }
            // An item without a comma after it is the last.
            if !consume(.comma) { break }
        }
        try expect(.rparen, else: unclosed)
    }

    /// Skips the rest of a failed header item, which began at the token at `start`, up to the comma or `)` after it.
    /// A `{` stops it only where the list's `)` isn't ahead, since then the `{` may begin the body.
    private mutating func skipFailedItem(openedSince start: Int) {
        let open = bracketsLeftOpen(since: start)
        let listClosesAhead = closingParenthesisAhead(insideBrackets: open) != nil
        let stops: [Punct] = listClosesAhead ? [.comma, .rparen] : [.comma, .rparen, .lbrace]
        recover(upTo: stops, insideBrackets: open)
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

    /// How many tokens past the current one the `)` at its level comes, or nil where the declaration ends first. `open`
    /// counts the brackets the current token is inside, which close before that level.
    private func closingParenthesisAhead(insideBrackets open: Int = 0) -> Int? {
        var depth = open
        var ahead = 0
        while true {
            let token = peek(ahead)
            if token.kind == .eof { return nil }
            // At the parser's level, a `)` closes the bracket it is in, unless the declaration ends first.
            if depth == 0, token.isPunct(.rparen) { return ahead }
            if depth == 0, token.endsStatement { return nil }
            depth = token.bracketDepth(from: depth)
            ahead += 1
        }
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it, the `}` after it, the end of the
    /// file, or one of `stops` outside the item's brackets. `open` counts those it opened before it failed.
    mutating func recover(upTo stops: [Punct] = [], insideBrackets open: Int = 0) {
        var depth = open
        while !atEnd {
            // Outside the item's brackets, the end of its statement or one of `stops` ends it.
            if depth == 0, atStatementEnd || stops.contains(where: current.isPunct) { return }
            // Every other token is skipped, a bracket with all it holds, and a stray closer on its own.
            depth = current.bracketDepth(from: depth)
            advance()
        }
    }
}
