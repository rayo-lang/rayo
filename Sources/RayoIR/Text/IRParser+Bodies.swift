import RayoSema

extension IRParser {
    /// Reads a function's body between braces: its locals, then its blocks.
    mutating func body() throws(IRTextError) -> IRBody {
        try expect("{")
        localCount = 0
        blockReferences = []

        // The locals come first, each numbered by its ID.
        var locals: [IRLocal] = []
        while let local = try local() {
            locals.append(local)
            localCount += 1
        }

        // Each block follows under its label, numbered by its ID.
        var blocks: [BasicBlock] = []
        while !consume("}") {
            blocks.append(try block(numbered: blocks.count))
        }

        // A block that a terminator names must be among them.
        for reference in blockReferences where reference.block.index >= blocks.count {
            throw IRTextError(at: reference.token, "no block is labelled bb\(reference.block.index)")
        }
        return IRBody(locals: locals, blocks: blocks)
    }

    /// Reads `kind %N name: Type`, or `temp %N: Type`, where `N` is the local's ID; or nil where the current token
    /// starts no local.
    private mutating func local() throws(IRTextError) -> IRLocal? {
        guard case .word(let keyword) = current.kind else { return nil }
        let kind: LocalKind? = switch keyword {
        case "let": .let
        case "var": .var
        case "param": .parameter
        default: nil
        }
        guard kind != nil || keyword == "temp" else { return nil }
        advance()

        // The local's number is its ID, so the locals come in order.
        try expect("%")
        let number = current
        guard try integer() == localCount else { throw IRTextError(at: number, "expected the local %\(localCount)") }

        // A temporary has a type alone, and a local the source declares a name before it.
        guard let kind else {
            try expect(":")
            return .temporary(try type())
        }
        let name = try word()
        try expect(":")
        return .source(name: name, kind: kind, type: try type())
    }

    /// Reads `bbN:`, then the block's statements, then its terminator.
    private mutating func block(numbered index: Int) throws(IRTextError) -> BasicBlock {
        let label = current
        guard try word() == "bb\(index)" else { throw IRTextError(at: label, "expected the label bb\(index)") }
        try expect(":")

        var statements: [Statement] = []
        while let statement = try statement() {
            statements.append(statement)
        }
        return BasicBlock(statements: statements, terminator: try terminator())
    }

    /// Reads `declare %N`, or `destination = value @range`; or nil where the current token starts no statement.
    private mutating func statement() throws(IRTextError) -> Statement? {
        switch current.kind {
        case .word("declare"): try declaration()
        // A computation stores its value in a place, or drops it where the text writes `_`.
        case .word("_"), .symbol("%"): try computation()
        default: nil
        }
    }

    /// Reads `declare %N`.
    private mutating func declaration() throws(IRTextError) -> Statement {
        try expect(word: "declare")
        return .declare(try localReference())
    }

    /// Reads `destination = value @range`.
    private mutating func computation() throws(IRTextError) -> Statement {
        let destination = try destination()
        try expect("=")
        let value = try rvalue()
        return .compute(destination: destination, value: value, range: try range())
    }

    /// Reads `_`, which drops a computation's value, or a place and where the source names it.
    private mutating func destination() throws(IRTextError) -> Destination? {
        guard current.kind != .word("_") else {
            advance()
            return nil
        }
        let place = try place()
        return Destination(place, at: try range())
    }

    /// Reads `goto bbN`, `branch condition, bbN, bbM`, `return`, `return result` or `unreachable`.
    private mutating func terminator() throws(IRTextError) -> Terminator {
        // A terminator starts with the word that names it, which the rest of it follows.
        if consume(word: "goto") { return .goto(try blockReference()) }
        if consume(word: "branch") { return try branch() }
        if consume(word: "return") { return .return(startsOperand ? try operand() : nil) }
        if consume(word: "unreachable") { return .unreachable }
        throw expected("a statement or a terminator")
    }

    /// Reads `condition, bbN, bbM`, the rest of a branch.
    private mutating func branch() throws(IRTextError) -> Terminator {
        let condition = try operand()
        try expect(",")
        let then = try blockReference()
        try expect(",")
        return .branch(condition, then: then, otherwise: try blockReference())
    }

    /// Reads `bbN`, a block that the function's blocks must hold.
    private mutating func blockReference() throws(IRTextError) -> BlockID {
        let token = current
        let label = try word()
        guard label.hasPrefix("bb"), let index = Int(label.dropFirst(2)) else {
            throw IRTextError(at: token, "expected a block's label, found '\(label)'")
        }
        blockReferences.append((BlockID(index: index), token))
        return BlockID(index: index)
    }

    /// Reads `%N`, a local the function declares.
    mutating func localReference() throws(IRTextError) -> LocalID {
        try expect("%")
        let token = current
        let index = try integer()
        guard index < localCount else { throw IRTextError(at: token, "no local is numbered %\(index)") }
        return LocalID(index: index)
    }
}
