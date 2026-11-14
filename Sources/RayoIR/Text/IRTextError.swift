/// Why a text isn't Rayo IR, and where in the text the parser found out.
public struct IRTextError: Error, Equatable, CustomStringConvertible {
    /// The 1-based line of the text the parser stopped at.
    public var line: Int
    /// The 1-based column, in bytes, of the text the parser stopped at.
    public var column: Int
    /// What the parser found wrong there, such as `expected a type, found '{'`.
    public var message: String

    public init(line: Int, column: Int, message: String) {
        self.line = line
        self.column = column
        self.message = message
    }

    public var description: String {
        "\(line):\(column): \(message)"
    }
}

extension IRTextError {
    /// The error `message`, at the start of `token`.
    init(at token: IRToken, _ message: String) {
        self.init(line: token.line, column: token.column, message: message)
    }
}
