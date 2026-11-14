import RayoDiagnostics
import RayoSyntax

/// Parses a file's source into its syntax tree, and adds its syntax errors to the compile's errors. The tree keeps what
/// failed to parse, so the steps after this one check the rest; a file that isn't UTF-8 makes no tree.
struct Parse: CompilationStep {
    func run(_ source: [UInt8], errors: inout [Diagnostic]) -> SourceFile? {
        let (file, diagnostics) = Parser.parse(source)
        errors += diagnostics
        return file
    }
}
