import RayoSyntax

/// Parses a file's source into its syntax tree.
struct Parse: CompilationStep {
    func run(_ source: [UInt8]) throws(CompilationError) -> SourceFile {
        let (file, diagnostics) = Parser.parse(source)
        // A file with syntax errors is rejected with them.
        guard diagnostics.isEmpty else { throw .rejected(diagnostics) }
        return file
    }
}
