/// Reserved words. Contextual keywords, such as `keep` and `move`, lex as identifiers.
public enum Keyword: String, Sendable, CaseIterable {
    case `let`, `var`, `const`, `func`, task, `struct`, `enum`, `protocol`, `extension`, `typealias`, `import`
    case `public`, `private`, `init`, `deinit`, `self`, `Self`, `if`, `else`, `guard`, when, `case`, `for`, `in`
    case `while`, `repeat`, `break`, `continue`, `return`, `throw`, `throws`, `try`, `catch`, `do`, `defer`
    case `static`, mutable, owned, consuming, copy, consume, mutating, any, some, `where`, with, await, yield
    case unsafe, unchecked, using, extern, `as`, `is`, `nil`, `true`, `false`, `associatedtype`, `subscript`
}

/// Punctuation and operators. The lexer takes the longest match, except that `>` is always alone, so
/// `List<List<Int>>` closes two argument lists; the parser rebuilds `>=` from adjacent `>` and `=`.
public enum Punct: String, Sendable, CaseIterable {
    case lparen = "(", rparen = ")", lbracket = "[", rbracket = "]", lbrace = "{", rbrace = "}"
    case comma = ",", colon = ":", semicolon = ";", dot = ".", at = "@", question = "?", bang = "!"
    case arrow = "->", assign = "="
    case plus = "+", minus = "-", star = "*", slash = "/", percent = "%"
    case amp = "&", pipe = "|", caret = "^", tilde = "~"
    case less = "<", greater = ">", lessEqual = "<=", shiftLeft = "<<"
    case equal = "==", notEqual = "!="
    case andAnd = "&&", orOr = "||", coalesce = "??"
    case halfOpenRange = "..<", closedRange = "..."
    case plusAssign = "+=", minusAssign = "-=", starAssign = "*=", slashAssign = "/=", percentAssign = "%="
    case ampAssign = "&=", pipeAssign = "|=", caretAssign = "^=", shiftLeftAssign = "<<="

    static let byLengthDescending: [Punct] = Punct.allCases.sorted { $0.rawValue.utf8.count > $1.rawValue.utf8.count }

    public var isAssignment: Bool {
        switch self {
        case .assign, .plusAssign, .minusAssign, .starAssign, .slashAssign, .percentAssign,
             .ampAssign, .pipeAssign, .caretAssign, .shiftLeftAssign:
            return true
        default:
            return false
        }
    }

    /// Whether this is a binary operator. `>` isn't one here, since only the parser can tell a comparison
    /// from the end of generic arguments.
    public var isBinaryOperator: Bool {
        switch self {
        case .plus, .minus, .star, .slash, .percent, .amp, .pipe, .caret, .less, .lessEqual, .shiftLeft,
             .equal, .notEqual, .andAnd, .orOr, .coalesce, .halfOpenRange, .closedRange:
            return true
        default:
            return false
        }
    }
}

public enum TokenKind: Sendable, Hashable {
    case identifier(String)
    case keyword(Keyword)
    /// The digits' value. A `-` in front is a separate token, so `-9223372036854775808` lexes.
    case intLiteral(UInt64)
    case punct(Punct)
    case newline
    case eof
    /// Text the lexer reported an error for, such as a string literal, which the subset doesn't have yet.
    /// The parser skips the statement that holds it without reporting it again.
    case invalid
}

public struct Token: Sendable, Hashable, CustomStringConvertible {
    public var kind: TokenKind
    public var range: SourceRange
    /// Whether whitespace or a comment separates this token from the one before it.
    public var spaceBefore: Bool

    public init(_ kind: TokenKind, _ range: SourceRange, spaceBefore: Bool) {
        self.kind = kind
        self.range = range
        self.spaceBefore = spaceBefore
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
        }
    }

    public func isPunct(_ punct: Punct) -> Bool { kind == .punct(punct) }
    public func isKeyword(_ keyword: Keyword) -> Bool { kind == .keyword(keyword) }
}
