import RayoSema
import RayoSource

extension IRParser {
    /// Every unary operator, each in each of its overflow modes.
    private static let unaryOperators: [IRUnaryOperator] = [.negate(.checked), .negate(.wrapping), .not]

    /// Every binary operator, each in each of its overflow modes.
    private static let binaryOperators: [IRBinaryOperator] = [
        .add(.checked), .add(.wrapping), .subtract(.checked), .subtract(.wrapping),
        .multiply(.checked), .multiply(.wrapping), .divide(.checked), .divide(.wrapping),
        .remainder, .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual,
    ]

    /// Reads the operation a computation makes its value with.
    mutating func rvalue() throws(IRTextError) -> Rvalue {
        let token = current
        let keyword = try word()
        switch keyword {
        case "use":
            return .use(try operand())
        case "call":
            let callee = try callee()
            return .call(callee, arguments: try operands())
        case "struct":
            let type = try type()
            guard case .structure(let id) = type else {
                throw IRTextError(at: token, "\(type) isn't a struct, so no value of it is made of fields")
            }
            return .structure(id, fields: try operands())
        default:
            return try operation(named: keyword, at: token)
        }
    }

    /// Reads the operands of the unary or binary operator whose name starts with `keyword`, which `token` holds, and
    /// the rest of whose name follows it.
    private mutating func operation(named keyword: String, at token: IRToken) throws(IRTextError) -> Rvalue {
        // An operator with an overflow mode names it in a second word.
        let takesMode = (Self.unaryOperators.map(IRPrinter.name(of:)) + Self.binaryOperators.map(IRPrinter.name(of:)))
            .contains { $0.hasPrefix(keyword + " ") }
        let name = takesMode ? "\(keyword) \(try word())" : keyword

        if let op = Self.unaryOperators.first(where: { IRPrinter.name(of: $0) == name }) {
            return .unary(op, try operand())
        }
        if let op = Self.binaryOperators.first(where: { IRPrinter.name(of: $0) == name }) {
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

    /// Reads a call's arguments, or a struct's fields, between parentheses.
    private mutating func operands() throws(IRTextError) -> [Operand] {
        try parenthesized { (parser: inout IRParser) throws(IRTextError) in try parser.operand() }
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
        case .word("true"), .word("false"):
            let value = current.kind == .word("true")
            advance()
            return .constant(.bool(value))
        case .word("read"):
            advance()
            let place = try place()
            return .read(place, at: try range())
        case .word("move"):
            advance()
            let place = try place()
            return .move(place, at: try range())
        case .integer, .symbol("-"):
            return .constant(.int(try intConstant()))
        default:
            throw expected("an operand")
        }
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
