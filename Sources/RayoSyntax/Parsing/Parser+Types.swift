internal import RayoDiagnostics
internal import RayoSource

/// Parses a type, wherever a declaration or a statement writes one.
extension Parser {
    /// `identifier`, `'(' ')'` or `'[' int-literal 'of' type ']'`.
    mutating func parseType() throws(ParseFailure) -> TypeExpr {
        let start = current.range

        // `()` is the Void type.
        if consume(.lparen) {
            try expect(.rparen, else: ErrorCode.unclosedEmptyParentheses)
            return .void(range: range(from: start))
        }
        // `[` starts an array type.
        if consume(.lbracket) {
            return try parseArrayType(from: start)
        }

        // Any other type is named.
        let (name, _) = try expectIdentifier(else: ErrorCode.missingType)
        return .named(name, range: range(from: start))
    }

    /// Whether a type can start with `token`.
    func startsType(_ token: Token) -> Bool {
        switch token.kind {
        case .identifier, .punct(.lparen), .punct(.lbracket): true
        default: false
        }
    }

    /// After the `[` at `start`: the count, `of`, the element's type and the `]`.
    private mutating func parseArrayType(from start: SourceRange) throws(ParseFailure) -> TypeExpr {
        // The count is an integer literal.
        guard case .intLiteral(let count) = current.kind else { throw fail(ErrorCode.missingArrayCount) }
        advance()

        // `of` is a word only here, so it lexes as an identifier.
        guard current.kind == .identifier("of") else { throw fail(ErrorCode.missingArrayOf) }
        advance()

        let element = try parseType()
        try expect(.rbracket, else: ErrorCode.unclosedArrayType)
        return .array(count: count, element: element, range: range(from: start))
    }
}
