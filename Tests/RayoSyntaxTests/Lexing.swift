import RayoDiagnostics
import Testing
import RayoSyntax

/// The tokens of `source`, written as the source spells them, with `⏎` for a newline that ends a statement.
func tokens(_ source: String) -> [String] {
    let (tokens, diagnostics) = Lexer.tokenize(source)
    #expect(diagnostics.map(\.code) == [])
    return tokens.dropLast().map { $0.kind == .newline ? "⏎" : $0.description }
}

func lexErrors(_ source: String) -> [ErrorCode] {
    Lexer.tokenize(source).diagnostics.map(\.code)
}

/// The source text each error the lexer reports for `source` covers.
func lexCoveredText(_ source: String) -> [String] {
    let bytes = Array(source.utf8)
    return Lexer.tokenize(source).diagnostics.map {
        String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self)
    }
}
