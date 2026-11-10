import RayoDiagnostics
import Testing
import RayoSyntax

/// The tokens of `source`, written as the source spells them, with `⏎` for a newline that ends a statement.
func tokens(_ source: String) -> [String] {
    let (tokens, diagnostics) = Lexer.tokenize(source)
    #expect(diagnostics.map(\.code) == [])
    return tokens.dropLast().map { $0.kind == .newline ? "⏎" : $0.description }
}
