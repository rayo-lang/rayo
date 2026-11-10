/// Where statements end: which newlines in a file's tokens end a statement, and which only break a line.
enum StatementEnds {
    /// Keeps the newlines that end a statement, and drops those that only break a line.
    static func significantNewlines(_ raw: [Token]) -> [Token] {
        var result: [Token] = []
        var brackets: [Punct] = []
        for (index, token) in raw.enumerated() {
            switch token.kind {
            // An opening bracket becomes the innermost one, which decides what a newline inside it means.
            case .punct(let bracket) where bracket == .lparen || bracket == .lbrace:
                brackets.append(bracket)

            // A closing bracket ends the innermost one; a stray one ends nothing.
            case .punct(.rparen), .punct(.rbrace):
                _ = brackets.popLast()

            // A newline is kept where it ends a statement, and each `continue` drops it where the statement goes on.
            case .newline:
                // Where `(` is the innermost bracket, a call's arguments and a grouped expression run across lines.
                if brackets.last == .lparen { continue }
                // A line that ends in a binary or assignment operator, `->`, `(` or `{` runs on into the next.
                if let previous = result.last, continuesLine(previous) { continue }
                // A line that starts with `->`, `{`, `else`, or a binary operator other than `-` joins the line above;
                // a `-` there starts a negation.
                if index + 1 < raw.count, joinsLine(raw[index + 1]) { continue }
                // A blank line, or a newline before the first statement, ends nothing.
                if result.isEmpty || result.last?.kind == .newline { continue }

            // Every other token needs no bookkeeping.
            default:
                break
            }

            // Keep every token that no test above dropped.
            result.append(token)
        }
        return result
    }

    /// Whether a line that ends in `token` runs on into the next line.
    private static func continuesLine(_ token: Token) -> Bool {
        // A name, a literal or a keyword can end a statement.
        guard case .punct(let punct) = token.kind else { return false }
        return punct.binaryOperator != nil || punct.assignOperator != nil || [.arrow, .lparen, .lbrace].contains(punct)
    }

    /// Whether a line that starts with `token` joins the line above.
    private static func joinsLine(_ token: Token) -> Bool {
        switch token.kind {
        // A `-` starts a negation, which can begin a statement of its own.
        case .punct(.minus):
            return false

        // A binary operator or `->` can't begin a statement, and a `{` can't either, so it opens the block of the
        // line above.
        case .punct(let punct):
            return punct.binaryOperator != nil || punct == .arrow || punct == .lbrace

        // An `else` goes on from the `if` above it.
        case .keyword(.else):
            return true

        // Any other token begins a statement.
        default:
            return false
        }
    }
}
