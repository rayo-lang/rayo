import Testing
import RayoCompiler
import RayoDiagnostics

/// The errors `rayoc --check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [ErrorCode] {
    diagnostics(source).map(\.code)
}

/// The source text each of `diagnostics` covers in `source`.
func coveredText(_ diagnostics: [Diagnostic], in source: String) -> [String] {
    let bytes = Array(source.utf8)
    return diagnostics.map { String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self) }
}

/// The diagnostics `rayoc --check` reports for `source`, saved as `main.rayo`.
func diagnostics(_ source: String) -> [Diagnostic] {
    let result = Compiler.run(["--check", "main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) {
        _, _ in false
    }
    #expect(result.exitCode == (result.diagnostics.contains { $0.severity == .error } ? 1 : 0))
    return result.diagnostics
}

/// The errors that `body`, as `main`'s body, reports, each as its position, code and message.
func errorLines(inMain body: String) -> [String] {
    diagnostics(mainSource(body)).map(\.description)
}

/// The codes of the errors that `body`, as `main`'s body, reports, and the text of `main.rayo` each covers.
func codesAndCoverage(inMain body: String) -> (codes: [ErrorCode], covered: [String]) {
    let source = mainSource(body)
    let reported = diagnostics(source)
    return (reported.map(\.code), coveredText(reported, in: source))
}

/// The source of a program whose `main` runs `body`.
func mainSource(_ body: String) -> String {
    "func main() {\n\(body)\n}"
}
