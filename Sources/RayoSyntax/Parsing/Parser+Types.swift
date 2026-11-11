import RayoDiagnostics

/// Parses a type, wherever a declaration or a statement writes one.
extension Parser {
    /// `identifier` or `'(' ')'`.
    func parseType() throws(ParseFailure) -> TypeExpr {
        let start = current.range

        // `()` is the Void type.
        if consume(.lparen) {
            try expect(.rparen, else: ErrorCode.unclosedEmptyParentheses)
            return .void(range: range(from: start))
        }

        // Any other type is named.
        let (name, _) = try expectIdentifier(else: ErrorCode.missingType)
        return .named(name, range: range(from: start))
    }
}
