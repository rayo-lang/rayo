import RayoSema
import RayoSource

extension IRParser {
    /// The type the word at the current token names: `Int`, `Bool`, `Void`, or a struct the text declares.
    mutating func type() throws(IRTextError) -> RayoType {
        let token = current
        let name = try word()
        return switch name {
        case "Int": .int
        case "Bool": .bool
        case "Void": .void
        default: .structure(try structID(named: name, at: token))
        }
    }

    /// The struct the text declares as `name`, which `token` holds.
    private func structID(named name: String, at token: IRToken) throws(IRTextError) -> StructID {
        guard let id = structIDs[name] else { throw IRTextError(at: token, "no type is named '\(name)'") }
        return id
    }

    /// The function the quoted name at the current token names.
    mutating func functionReference() throws(IRTextError) -> FunctionID {
        let token = current
        guard case .string(let name) = token.kind else { throw expected("a function's quoted name") }
        guard let id = functionIDs[name] else { throw IRTextError(at: token, "no function is named \"\(name)\"") }
        advance()
        return id
    }

    /// Reads the operation a computation makes its value with.
    mutating func rvalue() throws(IRTextError) -> Rvalue {
        let token = current
        let keyword = try word()
        return switch keyword {
        case "operand": .operand(try operand())
        case "call": .call(try callee(), arguments: try arguments())
        default: try operation(named: keyword, at: token)
        }
    }

    /// Reads the operands of the unary or binary operator whose name starts with `keyword`, which `token` holds, and
    /// the rest of whose name follows it.
    private mutating func operation(named keyword: String, at token: IRToken) throws(IRTextError) -> Rvalue {
        // An operator with an overflow mode names it in a second word.
        let unaryNames = IRUnaryOperator.allCases.map(IRPrinter.name(of:))
        let binaryNames = IRBinaryOperator.allCases.map(IRPrinter.name(of:))
        let takesMode = (unaryNames + binaryNames).contains { $0.hasPrefix(keyword + " ") }
        let name = takesMode ? "\(keyword) \(try word())" : keyword

        if let op = IRUnaryOperator.allCases.first(where: { IRPrinter.name(of: $0) == name }) {
            return .unary(op, try operand())
        }
        if let op = IRBinaryOperator.allCases.first(where: { IRPrinter.name(of: $0) == name }) {
            let left = try operand()
            try expect(",")
            return .binary(op, left, try operand())
        }
        throw IRTextError(at: token, "no operation is named '\(name)'")
    }

    /// Reads `builtin "name"`, a built-in of the prelude, or `"name"`, a function the text declares.
    private mutating func callee() throws(IRTextError) -> Callee {
        guard current.kind == .word("builtin") else { return .function(try functionReference()) }
        advance()

        // A built-in is named as a call names it, such as `print(_: Int)`.
        let token = current
        guard case .string(let name) = token.kind else { throw expected("a built-in's quoted name") }
        let builtin = Builtin.allCases.first { Callee.builtin($0).name(in: FunctionTable()) == name }
        guard let builtin else { throw IRTextError(at: token, "no built-in is named \"\(name)\"") }
        advance()
        return .builtin(builtin)
    }

    /// Reads a call's arguments between parentheses, each an access, `aN`, or an operand.
    private mutating func arguments() throws(IRTextError) -> [CallArgument] {
        try parenthesized { (parser: inout IRParser) throws(IRTextError) in
            guard case .word(let word) = parser.current.kind, Self.isAccessName(word) else {
                return .operand(try parser.operand())
            }
            return .access(try parser.accessReference())
        }
    }

    /// Whether `word` names an access: `a`, then digits.
    static func isAccessName(_ word: String) -> Bool {
        word.count > 1 && word.first == "a" && word.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Whether the current token starts an operand.
    var startsOperand: Bool {
        switch current.kind {
        case .integer, .symbol("-"), .word("true"), .word("false"), .word("read"), .word("move"): true
        default: false
        }
    }

    /// Reads a constant, `read place @range` or `move place @range`.
    mutating func operand() throws(IRTextError) -> Operand {
        switch current.kind {
        case .word("true"), .word("false"): .constant(.bool(boolConstant()))
        case .integer, .symbol("-"): .constant(.int(try intConstant()))
        case .word("read"): try placeOperand(Operand.read)
        case .word("move"): try placeOperand(Operand.move)
        default: throw expected("an operand")
        }
    }

    /// Reads `true` or `false`, which the current token holds.
    private mutating func boolConstant() -> Bool {
        let value = current.kind == .word("true")
        advance()
        return value
    }

    /// Reads an Int constant, with `-` before it where it is negative.
    private mutating func intConstant() throws(IRTextError) -> Int64 {
        let negative = consume("-")
        let token = current
        guard case .integer(let magnitude) = token.kind else { throw expected("a number") }
        advance()

        // The most negative Int has a magnitude one more than the most positive.
        let value = negative ? Int64(exactly: -Int128(magnitude)) : Int64(exactly: magnitude)
        guard let value else { throw IRTextError(at: token, "\(negative ? "-" : "")\(magnitude) isn't an Int") }
        return value
    }

    /// Reads the word that says how an operand uses a place, then the place and where the source names it, and
    /// gives them to `make`.
    private mutating func placeOperand(_ make: (Place, SourceRange) -> Operand) throws(IRTextError) -> Operand {
        advance()
        let place = try place()
        return make(place, try range())
    }

    /// Reads `%N`, then `.F` for each field a step leads into.
    mutating func place() throws(IRTextError) -> Place {
        let root = try localReference()
        var steps: [PlaceStep] = []
        while consume(".") {
            steps.append(.field(try integer()))
        }
        return Place(root: root, steps: steps)
    }

    /// Reads `@line:column-line:column`, a range of the source.
    mutating func range() throws(IRTextError) -> SourceRange {
        try expect("@")
        let start = try location()
        try expect("-")
        return SourceRange(start, try location())
    }

    /// Reads `line:column`, which names no offset, so the location's is 0.
    private mutating func location() throws(IRTextError) -> SourceLocation {
        let line = try integer()
        try expect(":")
        return SourceLocation(line: line, column: try integer(), offset: 0)
    }
}
