import RayoDiagnostics
import RayoSyntax

/// Parses a file's source into its syntax tree, and adds its syntax errors to the compile's errors.
struct Parse: CompilationStep {
    func run(_ source: [UInt8], errors: inout [Diagnostic]) -> SourceFile? {
        let (file, diagnostics) = Parser.parse(source)
        errors += diagnostics
        return file
    }
}
