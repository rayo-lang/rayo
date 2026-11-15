import Testing
import RayoCompiler
import RayoDiagnostics

/// The errors `rayoc --check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [ErrorCode] {
    diagnostics(source).map(\.code)
}

/// The diagnostics `rayoc --check` reports for `source`, saved as `main.rayo`.
func diagnostics(_ source: String) -> [Diagnostic] {
    let result = Compiler.run(["--check", "main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) {
        _, _ in false
    }
    #expect(result.exitCode == (result.diagnostics.contains { $0.severity == .error } ? 1 : 0))
    return result.diagnostics
}
