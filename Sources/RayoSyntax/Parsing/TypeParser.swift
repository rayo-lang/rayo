import RayoDiagnostics

/// Parses a type, wherever a declaration or a statement writes one.
struct TypeParser {
    let tokens: TokenStream

    /// `identifier` or `'(' ')'`.
    func parseType() throws(ParseFailure) -> TypeExpr {
        let start = tokens.current.range

        // `()` is the Void type.
        if tokens.consume(.lparen) {
            try tokens.expect(.rparen, else: ErrorCode.unclosedEmptyParentheses)
            return .void(range: tokens.range(from: start))
        }

        // Any other type is named.
        let (name, _) = try tokens.expectIdentifier(else: ErrorCode.missingType)
        return .named(name, range: tokens.range(from: start))
    }
}
