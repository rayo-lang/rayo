extension IRParser {
    var current: IRToken {
        tokens[position]
    }

    /// Moves past the current token, unless it ends the text.
    mutating func advance() {
        if current.kind != .end { position += 1 }
    }

    /// Moves past the current token where it is `symbol`, and returns whether it was.
    mutating func consume(_ symbol: String) -> Bool {
        guard current.kind == .symbol(symbol) else { return false }
        advance()
        return true
    }

    /// Moves past the current token, which must be `symbol`.
    mutating func expect(_ symbol: String) throws(IRTextError) {
        guard consume(symbol) else { throw expected("'\(symbol)'") }
    }

    /// Moves past the current token where it is the word `word`, and returns whether it was.
    mutating func consume(word: String) -> Bool {
        guard current.kind == .word(word) else { return false }
        advance()
        return true
    }

    /// Moves past the current token, which must be the word `expected`.
    mutating func expect(word expected: String) throws(IRTextError) {
        guard consume(word: expected) else { throw self.expected("'\(expected)'") }
    }

    /// The word at the current token, which it moves past.
    mutating func word() throws(IRTextError) -> String {
        guard case .word(let word) = current.kind else { throw expected("a name") }
        advance()
        return word
    }

    /// The number at the current token, which it moves past, and which must fit in an `Int`.
    mutating func integer() throws(IRTextError) -> Int {
        guard case .integer(let value) = current.kind, let integer = Int(exactly: value) else {
            throw expected("a number")
        }
        advance()
        return integer
    }

    /// The items `item` reads, separated by commas, between parentheses.
    mutating func parenthesized<Item>(
        _ item: (inout IRParser) throws(IRTextError) -> Item,
    ) throws(IRTextError) -> [Item] {
        try expect("(")
        var items: [Item] = []
        guard !consume(")") else { return items }
        repeat {
            items.append(try item(&self))
        } while consume(",")
        try expect(")")
        return items
    }

    /// The error of finding the current token where the text should hold `what`.
    func expected(_ what: String) -> IRTextError {
        IRTextError(at: current, "expected \(what), found \(current.kind)")
    }
}
