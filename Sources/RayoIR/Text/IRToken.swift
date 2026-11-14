/// A word, number, quoted name or symbol of Rayo IR's text, and where the text writes it.
struct IRToken: Equatable {
    enum Kind: Equatable, CustomStringConvertible {
        /// A keyword or a name, such as `func`, `bb2` or `Int`.
        case word(String)
        /// A number without a sign.
        case integer(UInt64)
        /// The text between double quotes, such as a function's name.
        case string(String)
        /// A punctuation mark, such as `{`, `%` or `->`.
        case symbol(String)
        /// The end of the text.
        case end

        /// The token as an error names it.
        var description: String {
            switch self {
            case .word(let word): "'\(word)'"
            case .integer(let value): "'\(value)'"
            case .string(let text): "\"\(text)\""
            case .symbol(let symbol): "'\(symbol)'"
            case .end: "the end of the text"
            }
        }
    }

    var kind: Kind
    var line: Int
    var column: Int
}
