import RayoDiagnostics

/// Parses the grammar's runs of items: statements and declarations, one to a line or `;`, and the arguments and
/// parameters a `(` opens, separated by commas. An item that fails in a run of statements or declarations is
/// skipped, so the run goes on to report the errors after it.
struct SequenceParser {
    let tokens: TokenStream

    /// Parses items separated by newlines or `;`, up to the `}` that closes their block or the end of the file,
    /// which it leaves for the caller. An item that fails is skipped, and its error stays reported.
    func parseSequence<T>(ifUnended unended: TokenStream.ErrorCase, _ item: () throws(ParseFailure) -> T) -> [T] {
        var items: [T] = []
        skipSeparators()
        while !tokens.current.isPunct(.rbrace) && !tokens.atEnd {
            do {
                items.append(try item())
                // An item that runs on past its end is reported, and the rest of it skipped.
                if !tokens.atStatementEnd { throw tokens.fail(unended) }
            } catch {
                // An item that failed is skipped, and the sequence goes on with the next one.
                recover()
            }
            skipSeparators()
        }
        return items
    }

    /// After a `(`: parses items separated by commas, with an optional trailing comma, and the `)`.
    func parseList<T>(ifUnclosed unclosed: TokenStream.ErrorCase,
                      _ item: () throws(ParseFailure) -> T) throws(ParseFailure) -> [T] {
        var items: [T] = []
        while !tokens.current.isPunct(.rparen) {
            items.append(try item())
            // An item without a comma after it is the last.
            if !tokens.consume(.comma) { break }
        }
        try tokens.expect(.rparen, else: unclosed)
        return items
    }

    private func skipSeparators() {
        while tokens.current.kind == .newline || tokens.current.isPunct(.semicolon) { tokens.advance() }
    }

    /// Skips the rest of an item that failed, up to the newline or `;` that ends it or the `}` that closes
    /// its block.
    private func recover() {
        var depth = 0
        loop: while !tokens.atEnd {
            switch tokens.current.kind {
            // A bracket the item opens is skipped whole, up to the bracket that closes it.
            case .punct(.lbrace), .punct(.lparen):
                depth += 1

            // A `}` outside the item's brackets closes its block, which the sequence stops at; inside, it closes one.
            case .punct(.rbrace):
                if depth == 0 { break loop }
                depth -= 1

            // A `)` closes one of the item's brackets; a stray one is skipped.
            case .punct(.rparen):
                if depth > 0 { depth -= 1 }

            // A newline or `;` outside the item's brackets ends it; inside them, it is skipped.
            case .newline, .punct(.semicolon):
                if depth == 0 { break loop }

            // Every other token is skipped.
            default:
                break
            }
            tokens.advance()
        }
    }
}
