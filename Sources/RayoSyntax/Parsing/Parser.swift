import RayoDiagnostics

/// A recursive-descent parser. It reports what it can't parse and recovers at the next statement, so one
/// run lists every syntax error.
public enum Parser {
    public static func parse(_ source: String) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        parse(Array(source.utf8))
    }

    /// Parses `bytes`, with the lexer's and the parser's diagnostics in source order.
    public static func parse(_ bytes: [UInt8]) -> (file: SourceFile, diagnostics: [Diagnostic]) {
        let tokens = TokenStream(bytes)
        let file = DeclarationParser(tokens: tokens).parseFile()
        return (file, tokens.diagnostics.inSourceOrder)
    }
}
