import RayoSema

/// Reads Rayo IR from the text `IRPrinter` writes, as a recursive-descent parser over its tokens.
///
/// The parser checks that every name and number the text uses is declared: each struct, function, built-in, local and
/// block. It doesn't check that the IR keeps its types, which `IRVerifier` does.
public struct IRParser {
    let tokens: [IRToken]
    var position = 0
    /// The ID of each struct the text declares, by its name.
    let structIDs: [String: StructID]
    /// The ID of each function the text declares, by its name.
    private let functionIDs: [String: FunctionID]
    /// The number of locals the function being read declares so far.
    var localCount = 0
    /// Each block the function being read names, and the token that names it, to check once its blocks are read.
    var blockReferences: [(block: BlockID, token: IRToken)] = []

    /// Starts at the first of `tokens`, with the structs and functions they declare at the top level numbered in
    /// order.
    private init(_ tokens: [IRToken]) throws(IRTextError) {
        self.tokens = tokens
        let (structNames, functionNames) = try Self.declaredNames(in: tokens)
        let structs = structNames.enumerated().map { ($1, StructID(index: $0, name: $1)) }
        let functions = functionNames.enumerated().map { ($1, FunctionID(index: $0)) }
        structIDs = Dictionary(uniqueKeysWithValues: structs)
        functionIDs = Dictionary(uniqueKeysWithValues: functions)
    }

    /// The program `text` writes. Throws, at the line and column it stops at, where the text isn't Rayo IR.
    public static func program(from text: String) throws(IRTextError) -> IRProgram {
        var parser = try IRParser(IRLexer.tokens(of: text))
        return try parser.program()
    }

    /// The names of the structs and the functions `tokens` declare outside every brace, each in the order of its
    /// declaration. Throws at a name declared twice.
    private static func declaredNames(
        in tokens: [IRToken],
    ) throws(IRTextError) -> (structs: [String], functions: [String]) {
        var structs: [String] = []
        var functions: [String] = []
        var depth = 0
        for (index, token) in tokens.enumerated() {
            let next = tokens[min(index + 1, tokens.count - 1)]
            switch (token.kind, next.kind) {
            case (.symbol("{"), _):
                depth += 1
            case (.symbol("}"), _):
                depth -= 1
            // A struct's declaration names it after `struct`, outside every brace; inside a body, `struct` makes one.
            case (.word("struct"), .word(let name)) where depth == 0:
                guard !structs.contains(name) else { throw IRTextError(at: next, "struct '\(name)' is declared twice") }
                structs.append(name)
            case (.word("func"), .string(let name)) where depth == 0:
                guard !functions.contains(name) else {
                    throw IRTextError(at: next, "function \"\(name)\" is declared twice")
                }
                functions.append(name)
            default:
                break
            }
        }
        return (structs, functions)
    }

    /// Reads the structs, the function a run starts at, and the functions, in any order, up to the end of the text.
    private mutating func program() throws(IRTextError) -> IRProgram {
        var structs: [StructType] = []
        var functions = FunctionTable()
        var bodies: [FunctionID: IRBody] = [:]
        var main: FunctionID?
        while current.kind != .end {
            let token = current
            switch token.kind {
            case .word("struct"):
                structs.append(try structDeclaration())
            case .word("main") where main == nil:
                main = try mainDeclaration()
            case .word("func"):
                let (declaration, body) = try function()
                bodies[functions.declare(declaration)] = body
            case .word("main"):
                throw IRTextError(at: token, "the function a run starts at is named twice")
            default:
                throw expected("'struct', 'main' or 'func'")
            }
        }
        return IRProgram(types: TypeTable(structs: structs), functions: functions, bodies: bodies, main: main)
    }

    /// Reads `struct Name { field: Type ... }`.
    private mutating func structDeclaration() throws(IRTextError) -> StructType {
        try expect(word: "struct")
        let name = try word()
        try expect("{")
        var fields: [Field] = []
        while !consume("}") {
            let fieldName = try word()
            try expect(":")
            fields.append(Field(name: fieldName, type: try type()))
        }
        return StructType(name: name, fields: fields)
    }

    /// Reads `main "name"`, the function a run starts at.
    private mutating func mainDeclaration() throws(IRTextError) -> FunctionID {
        try expect(word: "main")
        return try functionReference()
    }

    /// Reads `func "name"(Types) -> Type`, followed by the function's body where it has one.
    private mutating func function() throws(IRTextError) -> (FunctionDeclaration, IRBody?) {
        try expect(word: "func")
        guard case .string(let name) = current.kind else { throw expected("a function's quoted name") }
        advance()
        let parameters = try parenthesized { (parser: inout IRParser) throws(IRTextError) in try parser.type() }
        try expect("->")
        let result = try type()
        let declaration = FunctionDeclaration(name: name, parameters: parameters, result: result, kind: .written)

        // A function without a body ends at its result.
        guard current.kind == .symbol("{") else { return (declaration, nil) }
        return (declaration, try body())
    }

    /// The function the quoted name at the current token names.
    mutating func functionReference() throws(IRTextError) -> FunctionID {
        let token = current
        guard case .string(let name) = token.kind else { throw expected("a function's quoted name") }
        guard let id = functionIDs[name] else { throw IRTextError(at: token, "no function is named \"\(name)\"") }
        advance()
        return id
    }

    /// The type the word at the current token names: `Int`, `Bool`, `Void`, or a struct the text declares.
    mutating func type() throws(IRTextError) -> RayoType {
        let token = current
        let name = try word()
        switch name {
        case "Int": return .int
        case "Bool": return .bool
        case "Void": return .void
        default:
            guard let id = structIDs[name] else { throw IRTextError(at: token, "no type is named '\(name)'") }
            return .structure(id)
        }
    }
}
