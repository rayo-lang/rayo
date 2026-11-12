public import RayoSource

/// Reserved words. Other words, such as `keep`, lex as identifiers.
public enum Keyword: String, Sendable {
    case `let`, `var`, `func`, `struct`, `if`, `else`, `while`, `break`, `continue`, `return`, copy, `true`, `false`
}

/// Punctuation and operators. The lexer takes the longest match.
public enum Punct: String, Sendable, CaseIterable {
    case lparen = "(", rparen = ")", lbrace = "{", rbrace = "}"
    case comma = ",", colon = ":", semicolon = ";", bang = "!", dot = "."
    case arrow = "->", assign = "="
    case plus = "+", minus = "-", star = "*", slash = "/", percent = "%"
    case less = "<", greater = ">", lessEqual = "<=", greaterEqual = ">="
    case equal = "==", notEqual = "!="
    case andAnd = "&&", orOr = "||"
    case plusAssign = "+=", minusAssign = "-=", starAssign = "*=", slashAssign = "/=", percentAssign = "%="

    static let byLengthDescending: [Punct] = Punct.allCases.sorted { $0.rawValue.utf8.count > $1.rawValue.utf8.count }

    var unaryOperator: UnaryOperator? { UnaryOperator(rawValue: rawValue) }
    var binaryOperator: BinaryOperator? { BinaryOperator(rawValue: rawValue) }
    var assignOperator: AssignOperator? { AssignOperator(rawValue: rawValue) }
}

public enum TokenKind: Sendable, Hashable {
    case identifier(String)
    case keyword(Keyword)
    /// The digits' value. A `-` in front is a separate token, so `-9223372036854775808` lexes.
    case intLiteral(UInt64)
    case punct(Punct)
    case newline
    case eof
    /// Text the lexer reported an error for, which needs no second report.
    case invalid
    /// A character no token starts with, which the lexer leaves for the parser to report.
    case unexpected(String)
}

public struct Token: Sendable, Hashable, CustomStringConvertible {
    public var kind: TokenKind
    public var range: SourceRange

    public init(_ kind: TokenKind, _ range: SourceRange) {
        self.kind = kind
        self.range = range
    }

    public var description: String {
        switch kind {
        case .identifier(let name): return name
        case .keyword(let keyword): return keyword.rawValue
        case .intLiteral(let value): return String(value)
        case .punct(let punct): return punct.rawValue
        case .newline: return "newline"
        case .eof: return "end of file"
        case .invalid: return "invalid token"
        case .unexpected(let character): return character
        }
    }

    public func isPunct(_ punct: Punct) -> Bool { kind == .punct(punct) }
    public func isKeyword(_ keyword: Keyword) -> Bool { kind == .keyword(keyword) }

    /// How the token is spelled as an argument label, when it can be one: any identifier or keyword is one.
    var labelSpelling: String? {
        switch kind {
        case .identifier(let name): name
        case .keyword(let keyword): keyword.rawValue
        default: nil
        }
    }
}
